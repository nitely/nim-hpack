## Dynamic headers table

import ./exceptions
import ./utils

export
  exceptions

type DynHeadersError* = object of HpackError

type HBounds* = object
  ## Header's name and value boundaries
  # XXX maybe this should be uint16,
  #     but it'll limit the size to 32KB
  n*, v*: Slice[int32]

func initHBounds*(n, v: Slice[int]): HBounds {.inline.} =
  doAssert(
    n.a in 0 .. int32.high and
    n.b in -1 .. int32.high and
    v.a in 0 .. int32.high and
    v.b in -1 .. int32.high
  )
  HBounds(
    n: n.a.int32 .. n.b.int32,
    v: v.a.int32 .. v.b.int32
  )

type
  DynEntry = object
    pos: int  # virtual offset of the entry line
    nLen, vLen: int32
    # set only when indexed
    nHash, nvHash: uint32  # name, and name+value hashes
    nNext, nvNext: int  # older entry ids in the same buckets
  DynHeaders* = object
    ## The dynamic header table.
    ## It can be efficiently reused.
    ##
    ## Entries have increasing ids; live ids are
    ## ``firstId ..< nextId``. Entries are stored
    ## contiguously in ``buf`` as ``name: value\r\n``
    ## lines, the same format the decoder outputs, so
    ## they can be copied in and out at once. A virtual offset ``x``
    ## is located at ``buf[x - base]``. Evicted bytes at
    ## the front are reclaimed by compacting the buffer
    ## once it's full, which is amortized O(1).
    ##
    ## The encoder needs to find entries by name+value, and
    ## by name. The first lookup builds two hash indexes
    ## that ``add`` keeps up to date. Buckets contain the
    ## newest entry id with that hash, and each entry points
    ## to the next older one. Since evicted entries are
    ## always the oldest ones, a chain ends at the first
    ## evicted id, so there is no deletion.
    buf: string
    base, tail: int
    entries: seq[DynEntry]  # ring buffer indexed by id
    firstId, nextId: int
    nBuckets, nvBuckets: seq[int]  # empty when not indexed
    filled, size, initialSize, minSetSize: int
    maxSize*: int

const
  entryOverhead = 32
  lineOverhead = ": \r\n".len

func initDynHeaders*(strsize: int): DynHeaders {.inline.} =
  ## Initialize a dynamic headers table.
  ## ``strsize`` is the max size in bytes
  ## of all headers put together.
  doAssert strsize < int32.high div 2
  DynHeaders(
    size: strsize,
    maxSize: strsize,
    initialSize: strsize,
    minSetSize: strsize
  )

func len*(q: DynHeaders): int {.inline, raises: [].} =
  q.nextId - q.firstId

template entry(q: DynHeaders, id: int): untyped =
  q.entries[id and q.entries.high]

template entryAt(q: DynHeaders, i: Natural): untyped =
  ## Entry ``i``; ``0`` is the newest
  assert i < q.len
  q.entry(q.nextId-1-i)

func clear*(q: var DynHeaders) {.inline, raises: [].} =
  ## Efficiently clear the table
  q.firstId = q.nextId
  q.base = q.tail
  q.filled = 0
  q.minSetSize = 0

func reset*(q: var DynHeaders) {.deprecated.} =
  ## Deprecated, use ``clear()`` instead
  q.clear()

func head(q: DynHeaders): int {.inline.} =
  if q.len > 0: q.entry(q.firstId).pos else: q.tail

func pop(q: var DynHeaders) {.inline, raises: [].} =
  ## Remove the oldest entry
  doAssert q.len > 0, "empty queue"
  let e = q.entry(q.firstId)
  dec(q.filled, e.nLen+e.vLen+entryOverhead)
  inc q.firstId
  doAssert q.filled >= 0

func reserve(q: var DynHeaders, n: int) =
  ## Ensure there's room for ``n`` bytes at the tail
  if q.tail-q.base+n <= q.buf.len:
    return
  let head = q.head
  let live = q.tail-head
  if live+n <= q.buf.len div 2:
    if live > 0:
      moveMem(addr q.buf[0], addr q.buf[head-q.base], live)
  else:
    var buf = newString(max(64, (live+n)*2))
    if live > 0:
      copyMem(addr buf[0], addr q.buf[head-q.base], live)
    q.buf = move buf
  q.base = head

func indexed(q: DynHeaders): bool {.inline.} =
  q.nBuckets.len > 0

func index(q: var DynHeaders, id: int, nHash, nvHash: uint32) {.inline.} =
  template e: untyped = q.entry(id)
  e.nHash = nHash
  e.nvHash = nvHash
  let nb = nHash.int and q.nBuckets.high
  e.nNext = q.nBuckets[nb]
  q.nBuckets[nb] = id
  let nvb = nvHash.int and q.nvBuckets.high
  e.nvNext = q.nvBuckets[nvb]
  q.nvBuckets[nvb] = id

template nameImpl(q: DynHeaders, e: DynEntry): untyped =
  q.buf.toOpenArray(e.pos-q.base, e.pos-q.base+e.nLen-1)

template valueImpl(q: DynHeaders, e: DynEntry): untyped =
  q.buf.toOpenArray(e.pos-q.base+e.nLen+2, e.pos-q.base+e.nLen+2+e.vLen-1)

func rebuildIndex(q: var DynHeaders) =
  q.nBuckets.setLen(q.entries.len*2)
  q.nvBuckets.setLen(q.entries.len*2)
  for b in mitems q.nBuckets:
    b = -1
  for b in mitems q.nvBuckets:
    b = -1
  for id in q.firstId ..< q.nextId:
    let e = q.entry(id)
    let nHash = strhash(q.nameImpl(e))
    q.index(id, nHash, pairhash(nHash, q.valueImpl(e)))

func growEntries(q: var DynHeaders) =
  var entries = newSeq[DynEntry](max(16, q.entries.len*2))
  for id in q.firstId ..< q.nextId:
    entries[id and entries.high] = q.entry(id)
  q.entries = move entries
  if q.indexed:
    q.rebuildIndex()

func addEntry(q: var DynHeaders, nLen, vLen: int): int {.inline.} =
  ## Make room for a new entry and add it.
  ## Return the ``buf`` offset to write the entry line,
  ## or ``-1`` if it doesn't fit in the table
  let nvLen = nLen+vLen
  while q.len > 0 and nvLen > q.size-q.filled-entryOverhead:
    q.pop()
  if nvLen > q.size-entryOverhead:
    return -1
  if q.len == q.entries.len:
    q.growEntries()
  let lineLen = nvLen+lineOverhead
  q.reserve(lineLen)
  result = q.tail-q.base
  q.entry(q.nextId) = DynEntry(
    pos: q.tail,
    nLen: nLen.int32,
    vLen: vLen.int32
  )
  inc q.nextId
  inc(q.tail, lineLen)
  inc(q.filled, nvLen+entryOverhead)
  doAssert q.filled <= q.size

func add*(
  q: var DynHeaders, n, v: openArray[char], nHash, nvHash: uint32
) {.raises: [].} =
  ## Same as ``add``, but takes the hashes; they must be
  ## ``strhash(n)`` and ``pairhash(nHash, v)``
  let p = q.addEntry(n.len, v.len)
  if p == -1:
    return
  if n.len > 0:
    copyMem(addr q.buf[p], unsafeAddr n[0], n.len)
  q.buf[p+n.len] = ':'
  q.buf[p+n.len+1] = ' '
  if v.len > 0:
    copyMem(addr q.buf[p+n.len+2], unsafeAddr v[0], v.len)
  q.buf[p+n.len+2+v.len] = '\r'
  q.buf[p+n.len+3+v.len] = '\n'
  if q.indexed:
    q.index(q.nextId-1, nHash, nvHash)

func add*(q: var DynHeaders, n, v: openArray[char]) {.raises: [].} =
  ## Add a header name and value to the table.
  ## Evicts entries that no longer fit.
  ## Items are added and removed in FIFO order
  if q.indexed:
    let nHash = strhash(n)
    q.add(n, v, nHash, pairhash(nHash, v))
  else:
    q.add(n, v, 0, 0)

func addLine*(q: var DynHeaders, line: openArray[char], nLen: int) {.raises: [].} =
  ## Same as ``add``, but takes a ``name: value\r\n`` line,
  ## where ``nLen`` is the name length
  doAssert nLen+lineOverhead <= line.len
  doAssert line[nLen] == ':' and line[line.high] == '\n'
  let p = q.addEntry(nLen, line.len-nLen-lineOverhead)
  if p == -1:
    return
  copyMem(addr q.buf[p], unsafeAddr line[0], line.len)
  if q.indexed:
    let nHash = strhash(line.toOpenArray(0, nLen-1))
    let nvHash = pairhash(nHash, line.toOpenArray(nLen+2, line.len-3))
    q.index(q.nextId-1, nHash, nvHash)

func setSize*(q: var DynHeaders, strsize: Natural) {.raises: [].} =
  ## Resize the total headers max length.
  ## Evicts entries that don't fit anymore.
  ## Set to ``0`` to clear it.
  doAssert strsize < int32.high div 2
  q.minSetSize = min(q.minSetSize, strsize)
  q.size = strsize
  if strsize == 0:
    q.clear()
  while strsize < q.filled:
    q.pop()

func addStr(s: var string, x: openArray[char]) {.inline.} =
  # XXX Nim 2.0 lacks add(string, openArray[char])
  if x.len > 0:
    let L = s.len
    s.setLen(L+x.len)
    copyMem(addr s[L], unsafeAddr x[0], x.len)

func nameLen*(q: DynHeaders, i: Natural): int {.inline, raises: [].} =
  ## Length of the name of the ``i`` entry;
  ## ``0`` is the newest entry
  q.entryAt(i).nLen.int

func lineLen*(q: DynHeaders, i: Natural): int {.inline, raises: [].} =
  ## Length of the ``name: value\r\n`` line of the ``i`` entry;
  ## ``0`` is the newest entry
  let e = q.entryAt(i)
  e.nLen+e.vLen+lineOverhead

func copyName*(q: DynHeaders, i: Natural, d: var openArray[char]) {.inline, raises: [].} =
  ## Copy the name of the ``i`` entry into the start of ``d``
  let e = q.entryAt(i)
  doAssert d.len >= e.nLen
  if e.nLen > 0:
    copyMem(addr d[0], unsafeAddr q.buf[e.pos-q.base], e.nLen)

func copyLine*(q: DynHeaders, i: Natural, d: var openArray[char]) {.inline, raises: [].} =
  ## Copy the ``name: value\r\n`` line of the ``i``
  ## entry into the start of ``d``
  let e = q.entryAt(i)
  let L = e.nLen+e.vLen+lineOverhead
  doAssert d.len >= L
  copyMem(addr d[0], unsafeAddr q.buf[e.pos-q.base], L)

func ensureIndex(q: var DynHeaders) {.inline.} =
  if not q.indexed:
    if q.entries.len == 0:
      q.growEntries()
    q.rebuildIndex()

func find*(
  q: var DynHeaders, n, v: openArray[char], nvHash: uint32
): int {.raises: [].} =
  ## Return the index of the newest entry matching
  ## the name and value, or ``-1``; ``0`` is the newest entry.
  ## ``nvHash`` must be ``pairhash(strhash(n), v)``
  q.ensureIndex()
  var id = q.nvBuckets[nvHash.int and q.nvBuckets.high]
  while id >= q.firstId:
    template e: untyped = q.entry(id)
    if e.nvHash == nvHash and
        eqStr(q.nameImpl(e), n) and eqStr(q.valueImpl(e), v):
      return q.nextId-1-id
    id = e.nvNext
  return -1

func findName*(
  q: var DynHeaders, n: openArray[char], nHash: uint32
): int {.raises: [].} =
  ## Return the index of the newest entry matching
  ## the name, or ``-1``; ``0`` is the newest entry.
  ## ``nHash`` must be ``strhash(n)``
  q.ensureIndex()
  var id = q.nBuckets[nHash.int and q.nBuckets.high]
  while id >= q.firstId:
    template e: untyped = q.entry(id)
    if e.nHash == nHash and eqStr(q.nameImpl(e), n):
      return q.nextId-1-id
    id = e.nNext
  return -1

func `$`*(q: DynHeaders): string {.raises: [].} =
  ## Return all entries as ``name: value\r\n`` lines,
  ## newest first
  result = ""
  for i in 0 ..< q.len:
    result.addStr q.buf.toOpenArray(
      q.entryAt(i).pos-q.base,
      q.entryAt(i).pos-q.base+q.lineLen(i)-1
    )

func `==`*(a, b: DynHeaders): bool {.raises: [].} =
  ## Compare entries and sizes
  if a.len != b.len or a.filled != b.filled or a.size != b.size or
      a.maxSize != b.maxSize:
    return false
  for i in 0 ..< a.len:
    let x = a.entryAt(i)
    let y = b.entryAt(i)
    if not eqStr(a.nameImpl(x), b.nameImpl(y)) or
        not eqStr(a.valueImpl(x), b.valueImpl(y)):
      return false
  return true

func minSetSize*(q: DynHeaders): int {.raises: [].} =
  q.minSetSize

func finalSetSize*(q: DynHeaders): int {.raises: [].} =
  q.size

func hasResized*(q: DynHeaders): bool {.raises: [].} =
  # we only care about len decrease (entry eviction)
  # and final len. If it was increased and restored
  # we don't care, it's a no-op
  result =
    q.initialSize != q.minSetSize or
    q.minSetSize != q.finalSetSize

func clearLastResize*(q: var DynHeaders) {.raises: [].} =
  q.minSetSize = q.finalSetSize
  q.initialSize = q.finalSetSize

when isMainModule:
  func addName(s: var string, q: DynHeaders, i: Natural) =
    s.addStr q.nameImpl(q.entryAt(i))

  func addValue(s: var string, q: DynHeaders, i: Natural) =
    s.addStr q.valueImpl(q.entryAt(i))

  block:
    echo "Test DynHeaders"
    var dh = initDynHeaders(256)
    dh.add("cache-control", "private")
    dh.add("date", "Mon, 21 Oct 2013 20:13:21 GMT")
    dh.add("location", "https://www.example.com")
    dh.add(":status", "307")
    doAssert($dh ==
      ":status: 307\r\L" &
      "location: https://www.example.com\r\L" &
      "date: Mon, 21 Oct 2013 20:13:21 GMT\r\L" &
      "cache-control: private\r\L")
    dh.add("date", "Mon, 21 Oct 2013 20:13:22 GMT")
    dh.add("content-encoding", "gzip")
    dh.add("set-cookie", "foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; " &
      "max-age=3600; version=1")
    doAssert($dh ==
      "set-cookie: foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; " &
      "max-age=3600; version=1\r\L" &
      "content-encoding: gzip\r\L" &
      "date: Mon, 21 Oct 2013 20:13:22 GMT\r\L")
  block:
    echo "Test DynHeaders filled"
    var dh = initDynHeaders(256)
    dh.add("foo", "bar")
    doAssert dh.filled == "foobar".len+32
    dh.pop()
    doAssert dh.filled == 0
  block:
    var dh = initDynHeaders(256)
    var s = newString(256-32)
    for i in 0 .. s.len-1:
      s[i] = 'a'
    dh.add(s, "")
    doAssert dh.filled == 256
    dh.pop()
    doAssert dh.filled == 0
    dh.add(s, "")
    dh.add("a", "bc")
    doAssert dh.filled == "abc".len+32
  block:
    var dh = initDynHeaders(256)
    dh.add("a", "bc")
    dh.add("a", "bc")
    doAssert dh.filled == ("abc".len+32)*2
    dh.pop()
    doAssert dh.filled == "abc".len+32
    dh.pop()
    doAssert dh.filled == 0
  block:
    echo "Test DynHeaders length"
    var dh = initDynHeaders(1024)
    dh.add("foo", "bar")
    doAssert dh.len == 1
    dh.pop()
    doAssert dh.len == 0
    for _ in 0 ..< 4:
      dh.add("a", "bc")
    doAssert dh.len == 4
    for _ in 0 ..< 4:
      dh.pop()
    doAssert dh.len == 0
  block:
    echo "Test DynHeaders strsize"
    var dh = initDynHeaders(76)
    dh.add("asd", "asd")
    doAssert dh.filled == 38
    dh.add("qwe", "qwe")
    doAssert dh.filled == 76
    doAssert dh.len == 2
    var res = ""
    res.addName(dh, 0)
    res.addValue(dh, 0)
    doAssert res == "qweqwe"
    res = ""
    res.addName(dh, 1)
    res.addValue(dh, 1)
    doAssert res == "asdasd"
    dh.add("a", "")
    doAssert dh.filled == 71
    doAssert dh.len == 2
    res = ""
    res.addName(dh, 0)
    res.addValue(dh, 0)
    doAssert res == "a"
    res = ""
    res.addName(dh, 1)
    res.addValue(dh, 1)
    doAssert res == "qweqwe"
  block:
    echo "Test DynHeaders resize"
    var dh = initDynHeaders(256)
    dh.add("asd", "asd")
    dh.add("qwe", "qwe")
    dh.add("zxc", "zxc")
    doAssert dh.len == 3
    dh.setSize(100)
    doAssert dh.len == 2
    doAssert $dh ==
      "zxc: zxc\r\L" &
      "qwe: qwe\r\L"
    dh.setSize(0)
    doAssert dh.len == 0
    dh.add("zxc", "zxc")
    doAssert dh.len == 0
    dh.setSize(256)
    doAssert dh.len == 0
  block:
    echo "Test DynHeaders shrink"
    var dh = initDynHeaders(500)
    for _ in 0 .. 200:
      dh.add("asd", "qwe")
    dh.setSize(100)
    doAssert $dh ==
      "asd: qwe\r\L" &
      "asd: qwe\r\L"
  block:
    echo "Test DynHeaders grow"
    var dh = initDynHeaders(123)
    for _ in 0 .. 63:
      dh.add("zxc", "asdqw")
    dh.setSize(234)
    doAssert $dh ==
      "zxc: asdqw\r\L" &
      "zxc: asdqw\r\L" &
      "zxc: asdqw\r\L"
    for _ in 0 .. 63:
      dh.add("zxc", "asdqw")
    doAssert dh.len == 234 div (8+32)
  block:
    echo "Test DynHeaders find"
    template find(dh, n, v): untyped = dh.find(n, v, pairhash(strhash(n), v))
    template findName(dh, n): untyped = dh.findName(n, strhash(n))
    var dh = initDynHeaders(4096)
    doAssert dh.find("a", "b") == -1
    doAssert dh.findName("a") == -1
    dh.add("a", "b")
    dh.add("c", "d")
    dh.add("a", "e")
    doAssert dh.find("a", "b") == 2
    doAssert dh.findName("a") == 0
    doAssert dh.find("a", "e") == 0
    doAssert dh.find("c", "x") == -1
    doAssert dh.findName("c") == 1
    doAssert dh.find("x", "x") == -1
    doAssert dh.findName("x") == -1
    dh.addLine("c: x\r\n", 1)
    doAssert dh.find("c", "x") == 0
    doAssert dh.findName("c") == 0
  block:
    echo "Test DynHeaders find after evictions and growth"
    template find(dh, n, v): untyped = dh.find(n, v, pairhash(strhash(n), v))
    template findName(dh, n): untyped = dh.findName(n, strhash(n))
    var dh = initDynHeaders(32*4 + 4*2)
    for i in 0 ..< 1000:
      let n = $(i mod 10)
      dh.add(n, "v")
      doAssert dh.len == min(i+1, 4)
      doAssert dh.find(n, "v") == 0
      doAssert dh.findName(n) == 0
      if i >= 4:
        let old = $((i-4) mod 10)
        doAssert dh.find(old, "v") == -1
        doAssert dh.findName(old) == -1
    dh.setSize(4096)
    for i in 0 ..< 100:
      dh.add($i, "v")
    for i in 0 ..< 100:
      doAssert dh.find($i, "v") == 99-i
      doAssert dh.findName($i) == 99-i
  block:
    echo "Test DynHeaders eq"
    var a = initDynHeaders(256)
    var b = initDynHeaders(256)
    discard a.findName("x", strhash("x"))
    a.add("foo", "bar")
    b.add("foo", "bar")
    doAssert a == b
    b.add("foo", "baz")
    doAssert a != b
