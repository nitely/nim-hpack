## Dynamic headers table

import ./exceptions

export
  exceptions

type DynHeadersError* = object of HpackError

{.push checks: off.}
func strcopy(
  x: var openArray[char],
  y: openArray[char],
  xi, yi, xyLen: int
) {.inline, raises: [].} =
  assert x.len >= xi+xyLen
  assert y.len >= yi+xyLen
  for i in 0 ..< xyLen:
    x[xi+i] = y[yi+i]
{.pop.}

{.push checks: off.}
func strcmp(
  x, y: openArray[char],
  xi, yi, xyLen: int
): bool {.inline, raises: [].} =
  assert x.len >= xi+xyLen
  assert y.len >= yi+xyLen
  var diff = 0'u8
  for i in 0 ..< xyLen:
    diff = diff or (x[xi+i].uint8 xor y[yi+i].uint8)
  diff == 0
{.pop.}

{.push checks: off.}
template load(s: openArray[char], i: int, T: typedesc): uint64 =
  var r = 0'u64
  for j in 0 ..< sizeof(T):
    r = r or (s[i+j].uint64 shl (8*j))
  r

func load64(s: openArray[char], i: int): uint64 {.inline, raises: [].} =
  load(s, i, uint64)

func load32(s: openArray[char], i: int): uint64 {.inline, raises: [].} =
  load(s, i, uint32)

func mix(h: uint64): uint64 {.inline, raises: [].} =
  result = (h xor (h shr 32)) * 0xd6e8feb86659fd93'u64
  result = result xor (result shr 32)

func strhash*(s: openArray[char]): uint64 {.raises: [].} =
  ## Fast non-cryptographic hash
  const k = 0x9e3779b97f4a7c15'u64
  var h = s.len.uint64 * k
  var i = 0
  while i+8 < s.len:
    h = mix(h xor load64(s, i))
    inc(i, 8)
  # last 1 to 8 bytes; may overlap the previous ones
  if s.len >= 8:
    h = h xor load64(s, s.len-8)
  elif s.len >= 4:
    h = h xor (load32(s, 0) shl 32) xor load32(s, s.len-4)
  elif s.len > 0:
    h = h xor (s[0].uint64 shl 16) xor
      (s[s.len shr 1].uint64 shl 8) xor s[s.len-1].uint64
  mix(h * k)
{.pop.}

type HBounds* = object
  ## Header's name and value boundaries
  # XXX maybe this should be uint16,
  #     but it'll limit the size to 32KB
  n*, v*: Slice[int32]

func initHBounds*(n, v: Slice[int]): HBounds {.inline.} =
  doAssert(
    n.a in 0 .. int32.high and
    n.b in 0 .. int32.high and
    v.a in 0 .. int32.high and
    v.b in 0 .. int32.high
  )
  HBounds(
    n: n.a.int32 .. n.b.int32,
    v: v.a.int32 .. v.b.int32
  )

type DynHeaders* = object
  ## A circular queue.
  ## This is an implementaion of the
  ## dynamic header table.
  ## It can be efficiently reused.
  ## ``HBounds`` ends may be out of bounds and
  ## need to be wrapped around. All
  ## functions here take care of that
  s: string
  pos, filled: int
  bounds: seq[HBounds]
    ## ring of the entries' bounds, newest first;
    ## its len is a power of 2
  head, count: int
  size, maxSize*, initialSize, minSetSize: int
  # Hash index for ``find``. Each key maps to the newest entry with that key
  keys: seq[uint64]
    ## ring parallel to ``bounds``; the entry's
    ## name key and name+value key (32 bits each)
  slots: seq[uint64]
    ## open addressing; key shl 32 or ring pos+1, 0 is empty

func initDynHeaders*(strsize: int): DynHeaders {.inline.} =
  ## Initialize a dynamic headers table.
  ## ``strsize`` is the max size in bytes
  ## of all headers put together.
  doAssert strsize < int32.high div 2
  DynHeaders(
    s: newString(strsize),
    pos: 0,
    filled: 0,
    bounds: newSeq[HBounds](16),
    size: strsize,
    maxSize: strsize,
    initialSize: strsize,
    minSetSize: strsize
  )

func len*(q: DynHeaders): int {.inline, raises: [].} =
  q.count

func clear*(q: var DynHeaders) {.inline, raises: [].} =
  ## Efficiently clear the table
  q.pos = 0
  q.filled = 0
  q.head = 0
  q.count = 0
  q.minSetSize = 0
  for x in mitems q.slots:
    x = 0

func reset*(q: var DynHeaders) {.deprecated.} =
  ## Deprecated, use ``clear()`` instead
  q.clear()

{.push checks: off.}
func `[]`*(q: DynHeaders, i: Natural): HBounds {.inline, raises: [].} =
  assert i < q.count
  q.bounds[(q.head+i) and (q.bounds.len-1)]
{.pop.}

func len(hb: HBounds): int {.inline, raises: [].} =
  hb.n.len+hb.v.len

{.push checks: off.}
func keysOf(nh, vh: uint64): uint64 {.inline, raises: [].} =
  let pk = uint32(mix(nh * 0x9e3779b97f4a7c15'u64 xor vh))
  (nh and 0xffff_ffff'u64) shl 32 or pk

func nameKey(keys: uint64): uint64 {.inline, raises: [].} =
  keys shr 32

func pairKey(keys: uint64): uint64 {.inline, raises: [].} =
  keys and 0xffff_ffff'u64

func ringPos(q: DynHeaders, i: int): int {.inline, raises: [].} =
  (q.head+i) and (q.bounds.len-1)

func probe(q: DynHeaders, key: uint64): int {.inline, raises: [].} =
  ## Return the slot of ``key``, or the empty slot
  ## where it would go. The load is <= 50%,
  ## so there is always an empty slot
  let mask = q.slots.len-1
  result = key.int and mask
  while q.slots[result] != 0 and q.slots[result] shr 32 != key:
    result = (result+1) and mask

func slotPos(q: DynHeaders, key: uint64): int {.inline, raises: [].} =
  ## Return the ring pos of ``key``'s entry, or -1
  int(q.slots[q.probe(key)] and 0xffff_ffff'u64)-1

func index(q: var DynHeaders, key: uint64, pos: int) {.raises: [].} =
  ## Point the slot of ``key`` at ``pos``
  q.slots[q.probe(key)] = key shl 32 or uint64(pos+1)

func unindex(q: var DynHeaders, key: uint64, pos: int) {.raises: [].} =
  ## Remove the slot of ``key`` if it points at ``pos``.
  ## Backward-shift delete, so there are no tombstones
  let mask = q.slots.len-1
  var i = q.probe(key)
  if q.slots[i] != (key shl 32 or uint64(pos+1)):
    return
  var j = i
  while true:
    j = (j+1) and mask
    if q.slots[j] == 0:
      break
    let home = int(q.slots[j] shr 32) and mask
    if ((j-home) and mask) >= ((j-i) and mask):
      q.slots[i] = q.slots[j]
      i = j
  q.slots[i] = 0
{.pop.}

func reindex(q: var DynHeaders) {.raises: [].} =
  ## Size the index for ``bounds`` and fill it
  q.keys.setLen q.bounds.len
  q.slots.setLen q.bounds.len*4  # two keys per entry, <= 50% load
  for x in mitems q.slots:
    x = 0
  for i in countdown(q.count-1, 0):
    let pos = q.ringPos(i)
    q.index(q.keys[pos].nameKey, pos)
    q.index(q.keys[pos].pairKey, pos)

func left(q: DynHeaders): Natural {.inline, raises: [].} =
  ## Return available space
  q.size-q.filled

func pop(q: var DynHeaders): HBounds {.inline, raises: [].} =
  ## Return and remove header
  ## from the table in FIFO order
  doAssert q.len > 0, "empty queue"
  result = q[q.count-1]
  if q.slots.len > 0:
    let pos = q.ringPos(q.count-1)
    q.unindex(q.keys[pos].nameKey, pos)
    q.unindex(q.keys[pos].pairKey, pos)
  dec q.count
  dec(q.filled, result.len+32)
  doAssert q.filled >= 0

func add*(
  q: var DynHeaders,
  n, v: openArray[char],
  nh, vh: uint64
) {.raises: [].} =
  ## Same as ``add(q, n, v)``. ``nh`` and ``vh``
  ## must be ``strhash(n)`` and ``strhash(v)``
  let nvLen = v.len + n.len
  while q.len > 0 and nvLen > q.left-32:
    discard q.pop()
  if nvLen > q.size-32:
    return
  let hbn = q.pos .. q.pos+n.len-1
  let nLen = min(n.len, q.s.len-q.pos)
  strcopy(q.s, n, q.pos, 0, nLen)
  strcopy(q.s, n, 0, nLen, n.len-nLen)
  q.pos = q.pos+n.len  # n.len <= q.s.len
  if q.pos >= q.s.len:
    q.pos -= q.s.len
  let hbv = q.pos .. q.pos+v.len-1
  let vLen = min(v.len, q.s.len-q.pos)
  strcopy(q.s, v, q.pos, 0, vLen)
  strcopy(q.s, v, 0, vLen, v.len-vLen)
  q.pos = q.pos+v.len
  if q.pos >= q.s.len:
    q.pos -= q.s.len
  if q.count == q.bounds.len:
    var bounds = newSeq[HBounds](q.bounds.len*2)
    var keys = newSeq[uint64](if q.slots.len > 0: bounds.len else: 0)
    for i in 0 ..< q.count:
      bounds[i] = q[i]
      if q.slots.len > 0:
        keys[i] = q.keys[q.ringPos(i)]
    q.bounds = move bounds
    q.keys = move keys
    q.head = 0
    if q.slots.len > 0:
      q.reindex()
  q.head = (q.head-1) and (q.bounds.len-1)
  q.bounds[q.head] = initHBounds(hbn, hbv)
  inc q.count
  if q.slots.len > 0:
    q.keys[q.head] = keysOf(nh, vh)
    q.index(q.keys[q.head].nameKey, q.head)
    q.index(q.keys[q.head].pairKey, q.head)
  inc(q.filled, nvLen+32)
  doAssert q.filled <= q.size

func add*(q: var DynHeaders, n, v: openArray[char]) {.raises: [].} =
  ## Add a header name and value to the table.
  ## Evicts entries that no longer fit.
  ## Items are added and removed in FIFO order
  if q.slots.len > 0:
    q.add(n, v, strhash(n), strhash(v))
  else:
    q.add(n, v, 0, 0)

func setSize*(q: var DynHeaders, strsize: Natural) {.raises: [].} =
  ## Resize the total headers max length.
  ## Evicts entries that don't fit anymore.
  ## Set to ``0`` to clear it.
  doAssert strsize < int32.high div 2
  q.minSetSize = min(q.minSetSize, strsize)
  q.size = strsize
  # shrinking cannot be done efficiently
  # because of wrap around, so we don't ever shrink
  # + Nim won't shrink strings anyway
  # and grow needs to un-wrap around the headers
  if strsize > q.s.len:
    let oldLen = q.s.len
    q.s.setLen max(strsize, oldLen*2)
    for i in 0 .. oldLen-1:
      q.s[oldLen+i] = q.s[i]
  if strsize == 0:
    q.clear()
  while strsize < q.filled:
    discard q.pop()

iterator items*(q: DynHeaders): HBounds {.inline, raises: [].} =
  for i in 0 ..< q.count:
    yield q[i]

iterator pairs*(q: DynHeaders): (int, HBounds) {.inline, raises: [].} =
  for i in 0 ..< q.count:
    yield (i, q[i])

func substr*(q: DynHeaders, s: var string, x: Slice[int32]) {.raises: [].} =
  doAssert x.b+1 >= x.a
  let sLen = s.len
  let bLen = x.len
  s.setLenUninit(sLen+bLen)
  let mLen = min(bLen, q.s.len-x.a)
  strcopy(s, q.s, sLen, x.a, mLen)
  strcopy(s, q.s, sLen+mLen, 0, bLen-mLen)

func `==`*(a, b: DynHeaders): bool {.raises: [].} =
  ## Compare the entries, not the ring layout
  for i in 0 ..< min(a.len, b.len):
    if a[i] != b[i]:
      return false
  a.len == b.len and a.s == b.s and
    a.pos == b.pos and a.filled == b.filled and
    a.size == b.size and a.maxSize == b.maxSize and
    a.initialSize == b.initialSize and a.minSetSize == b.minSetSize

func `$`*(q: DynHeaders): string {.raises: [].} =
  ## Use it for debugging purposes only.
  ## Use ``substr`` and ``cmp`` for anything else
  result = ""
  for hb in q:
    q.substr(result, hb.n)
    result.add(": ")
    q.substr(result, hb.v)
    result.add("\r\L")

func cmp*(
  q: DynHeaders,
  b: Slice[int32],
  s: openArray[char]
): bool {.inline, raises: [].} =
  ## Efficiently compare a header name
  ## or value against a string
  if b.len != s.len:
    return false
  let mLen = min(b.len, q.s.len-b.a)
  result =
    strcmp(s, q.s, 0, b.a, mLen) and
    strcmp(s, q.s, mLen, 0, b.len-mLen)
    #s.toOpenArray(0, mLen-1) == q.s.toOpenArray(b.a, b.a+mLen-1) and
    #s.toOpenArray(mLen, b.len-1) == q.s.toOpenArray(0, b.len-mLen-1)

func buildIndex(q: var DynHeaders) {.raises: [].} =
  q.keys.setLen q.bounds.len
  var n, v = ""
  for i in 0 ..< q.count:
    n.setLen 0
    v.setLen 0
    q.substr(n, q[i].n)
    q.substr(v, q[i].v)
    q.keys[q.ringPos(i)] = keysOf(strhash(n), strhash(v))
  q.reindex()

func find*(
  q: var DynHeaders,
  n, v: openArray[char],
  nh, vh: uint64
): tuple[i: int, exact: bool] {.raises: [].} =
  ## Return the index of the newest entry matching
  ## name and value, or else the newest matching name,
  ## or -1. ``nh`` and ``vh`` must be
  ## ``strhash(n)`` and ``strhash(v)``
  if q.slots.len == 0:
    q.buildIndex()
  if q.count == 0:
    return (-1, false)
  # keys may collide, so compare the strings
  let keys = keysOf(nh, vh)
  var pos = q.slotPos(keys.pairKey)
  if pos != -1 and q.cmp(q.bounds[pos].n, n) and q.cmp(q.bounds[pos].v, v):
    return ((pos-q.head) and (q.bounds.len-1), true)
  pos = q.slotPos(keys.nameKey)
  if pos != -1 and q.cmp(q.bounds[pos].n, n):
    return ((pos-q.head) and (q.bounds.len-1), false)
  (-1, false)

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
    doAssert dh.pop() == initHBounds(
      0 ..< "foo".len,
      "foo".len .. "foobar".len-1
    )
    doAssert dh.filled == 0
  block:
    var dh = initDynHeaders(256)
    var s = newString(256-32)
    for i in 0 .. s.len-1:
      s[i] = 'a'
    dh.add(s, "")
    doAssert dh.filled == 256
    discard dh.pop()
    doAssert dh.filled == 0
    dh.add(s, "")
    dh.add("a", "bc")
    doAssert dh.filled == "abc".len+32
  block:
    var dh = initDynHeaders(256)
    dh.add("a", "bc")
    dh.add("a", "bc")
    doAssert dh.filled == ("abc".len+32)*2
    discard dh.pop()
    doAssert dh.filled == "abc".len+32
    discard dh.pop()
    doAssert dh.filled == 0
  block:
    echo "Test DynHeaders length"
    var dh = initDynHeaders(1024)
    dh.add("foo", "bar")
    doAssert dh.len == 1
    discard dh.pop()
    doAssert dh.len == 0
    for _ in 0 ..< 4:
      dh.add("a", "bc")
    doAssert dh.len == 4
    for _ in 0 ..< 4:
      discard dh.pop()
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
    dh.substr(res, dh[0].n)
    dh.substr(res, dh[0].v)
    doAssert res == "qweqwe"
    res = ""
    dh.substr(res, dh[1].n)
    dh.substr(res, dh[1].v)
    doAssert res == "asdasd"
    dh.add("a", "")
    doAssert dh.filled == 71
    doAssert dh.len == 2
    res = ""
    dh.substr(res, dh[0].n)
    dh.substr(res, dh[0].v)
    doAssert res == "a"
    res = ""
    dh.substr(res, dh[1].n)
    dh.substr(res, dh[1].v)
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
    # test for out of bounds wrap around bug
    echo "Test DynHeaders shrink"
    var dh = initDynHeaders(500)
    for _ in 0 .. 200:
      dh.add("asd", "qwe")
    dh.setSize(100)
    doAssert $dh ==
      "asd: qwe\r\L" &
      "asd: qwe\r\L"
  block:
    # test for wrap around bug
    echo "Test DynHeaders grow"
    var dh = initDynHeaders(123)
    for _ in 0 .. 63:
      dh.add("zxc", "asdqw")
    dh.setSize(234)
    #echo $dh
    doAssert $dh ==
      "zxc: asdqw\r\L" &
      "zxc: asdqw\r\L" &
      "zxc: asdqw\r\L"
  block:
    echo "Test DynHeaders grow 2"
    var dh = initDynHeaders(123)
    for _ in 0 .. 63:
      dh.add("zxc", "asdqw")
    dh.setSize(256)
    #echo $dh
    doAssert $dh ==
      "zxc: asdqw\r\L" &
      "zxc: asdqw\r\L" &
      "zxc: asdqw\r\L"
  block:
    echo "Test DynHeaders grow 3"
    var dh = initDynHeaders(123)
    for _ in 0 .. 63:
      dh.add("zxc", "asdqw")
    dh.setSize(124)
    #echo $dh
    doAssert $dh ==
      "zxc: asdqw\r\L" &
      "zxc: asdqw\r\L" &
      "zxc: asdqw\r\L"
  block:
    echo "Test DynHeaders grow 4"
    var dh = initDynHeaders(123)
    dh.add("zxc", "asdqw")
    dh.setSize(234)
    #echo $dh
    doAssert $dh ==
      "zxc: asdqw\r\L"
