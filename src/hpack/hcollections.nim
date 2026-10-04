## Dynamic headers table

{.push raises: [].}

import
  ./utils,
  ./ring

type
  HpackBound* = object
    ## Header's name and value boundaries
    # XXX maybe this should be uint16,
    #     but it'll limit the size to 32KB
    n*, v*: Slice[int32]
  HBounds* = HpackBound

func initHpackBound*(n, v: Slice[int]): HpackBound {.inline.} =
  doAssert(
    n.a in 0 .. int32.high and
    n.b in -1 .. int32.high and
    v.a in 0 .. int32.high and
    v.b in -1 .. int32.high
  )
  HpackBound(
    n: n.a.int32 .. n.b.int32,
    v: v.a.int32 .. v.b.int32
  )

func initHBounds*(n, v: Slice[int]): HBounds {.deprecated: "use initHpackBound".} =
  initHpackBound(n, v)

type
  Hpack* = object
    ## A circular queue.
    ## This is an implementaion of the
    ## dynamic header table.
    ## It can be efficiently reused.
    ## ``HpackBound`` ends may be out of bounds and
    ## need to be wrapped around. All
    ## functions here take care of that
    s: seq[byte]
    pos, filled: int
    bounds: Ring[HpackBound]
    size, maxSize*, initialSize, minSetSize: int
  DynHeaders* = Hpack

func initHpack*(strsize: int): Hpack {.inline.} =
  ## Initialize a dynamic headers table.
  ## ``strsize`` is the max size in bytes
  ## of all headers put together.
  doAssert strsize < int32.high div 2
  Hpack(
    s: newSeq[byte](strsize),
    pos: 0,
    filled: 0,
    size: strsize,
    maxSize: strsize,
    initialSize: strsize,
    minSetSize: strsize
  )

func initDynHeaders*(strsize: int): DynHeaders {.deprecated: "use initHpack".} =
  initHpack(strsize)

func len*(q: Hpack): int {.inline.} =
  q.bounds.len

func clear*(q: var Hpack) {.inline.} =
  ## Efficiently clear the table
  q.pos = 0
  q.filled = 0
  q.bounds.clear()
  q.minSetSize = 0

func reset*(q: var Hpack) {.deprecated.} =
  ## Deprecated, use ``clear()`` instead
  q.clear()

func `[]`*(q: Hpack, i: int): lent HpackBound {.inline.} =
  q.bounds[i]

func len(hb: HpackBound): int {.inline.} =
  hb.n.len+hb.v.len

func left(q: Hpack): int {.inline.} =
  ## Return available space
  q.size-q.filled

func pop(q: var Hpack): HpackBound {.inline.} =
  ## Return and remove header
  ## from the table in FIFO order
  doAssert q.len > 0, "empty queue"
  result = q.bounds.popLast()
  dec(q.filled, result.len+32)
  doAssert q.filled >= 0

func add*(q: var Hpack, n, v: openArray[byte]) =
  ## Add a header name and value to the table.
  ## Evicts entries that no longer fit.
  ## Items are added and removed in FIFO order
  let nvLen = v.len + n.len
  while q.len > 0 and nvLen > q.left-32:
    discard q.pop()
  if nvLen > q.size-32:
    return
  let hbn = q.pos .. q.pos+n.len-1
  let nLen = min(n.len, q.s.len-q.pos)
  strcopy(q.s, n, q.pos, 0, nLen)
  strcopy(q.s, n, 0, nLen, n.len-nLen)
  q.pos = (q.pos+n.len) mod q.s.len
  let hbv = q.pos .. q.pos+v.len-1
  let vLen = min(v.len, q.s.len-q.pos)
  strcopy(q.s, v, q.pos, 0, vLen)
  strcopy(q.s, v, 0, vLen, v.len-vLen)
  q.pos = (q.pos+v.len) mod q.s.len
  q.bounds.addFirst initHpackBound(hbn, hbv)
  inc(q.filled, nvLen+32)
  doAssert q.filled <= q.size

func setSize*(q: var Hpack, strsize: int) =
  ## Resize the total headers max length.
  ## Evicts entries that don't fit anymore.
  ## Set to ``0`` to clear it.
  doAssert strsize < int32.high div 2
  q.minSetSize = min(q.minSetSize, strsize)
  q.size = strsize
  # shrinking cannot be done efficiently
  # because of wrap around, so we don't ever shrink
  # + Nim won't shrink seqs anyway
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

iterator items*(q: Hpack): lent HpackBound {.inline.} =
  let L = len(q)
  for i in 0 ..< q.len:
    yield q[i]
    assert(len(q) == L, "the length changed while iterating")

iterator pairs*(q: Hpack): (int, HpackBound) {.inline.} =
  let L = len(q)
  for i in 0 ..< q.len:
    yield (i, q[i])
    assert(len(q) == L, "the length changed while iterating")

func substr*(q: Hpack, s: var seq[byte], x: Slice[int32]) =
  doAssert x.b+1 >= x.a
  let sLen = s.len
  let bLen = x.len
  s.setLenUninit2(sLen+bLen)
  let mLen = min(bLen, q.s.len-x.a)
  strcopy(s, q.s, sLen, x.a, mLen)
  strcopy(s, q.s, sLen+mLen, 0, bLen-mLen)

func `==`*(a, b: Hpack): bool =
  for x, y in fields(a, b):
    if x != y:
      return false
  true

func `$`*(q: Hpack): string =
  ## Use it for debugging purposes only.
  ## Use ``substr`` and ``cmp`` for anything else
  var s = newSeq[byte]()
  for hb in q:
    q.substr(s, hb.n)
    s.add ": ".asBytes
    q.substr(s, hb.v)
    s.add "\r\L".asBytes
  s.toString

func cmp(
  q: Hpack,
  b: Slice[int32],
  s: openArray[byte]
): bool {.inline.} =
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

func cmpN*(
  q: Hpack,
  i: int,
  s: openArray[byte]
): bool =
  assert i < q.len
  cmp(q, q[i].n, s)

func cmpV*(
  q: Hpack,
  i: int,
  s: openArray[byte]
): bool =
  assert i < q.len
  cmp(q, q[i].v, s)

func minSetSize*(q: Hpack): int =
  q.minSetSize

func finalSetSize*(q: Hpack): int =
  q.size

func hasResized*(q: Hpack): bool =
  # we only care about len decrease (entry eviction)
  # and final len. If it was increased and restored
  # we don't care, it's a no-op
  result =
    q.initialSize != q.minSetSize or
    q.minSetSize != q.finalSetSize

func clearLastResize*(q: var Hpack) =
  q.minSetSize = q.finalSetSize
  q.initialSize = q.finalSetSize

when isMainModule:
  block:
    echo "Test Hpack"
    var dh = initHpack(256)
    dh.add("cache-control".asBytes, "private".asBytes)
    dh.add("date".asBytes, "Mon, 21 Oct 2013 20:13:21 GMT".asBytes)
    dh.add("location".asBytes, "https://www.example.com".asBytes)
    dh.add(":status".asBytes, "307".asBytes)
    doAssert($dh ==
      ":status: 307\r\L" &
      "location: https://www.example.com\r\L" &
      "date: Mon, 21 Oct 2013 20:13:21 GMT\r\L" &
      "cache-control: private\r\L")
    dh.add("date".asBytes, "Mon, 21 Oct 2013 20:13:22 GMT".asBytes)
    dh.add("content-encoding".asBytes, "gzip".asBytes)
    dh.add("set-cookie".asBytes, ("foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; " &
      "max-age=3600; version=1").asBytes)
    doAssert($dh ==
      "set-cookie: foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; " &
      "max-age=3600; version=1\r\L" &
      "content-encoding: gzip\r\L" &
      "date: Mon, 21 Oct 2013 20:13:22 GMT\r\L")
  block:
    echo "Test Hpack filled"
    var dh = initHpack(256)
    dh.add("foo".asBytes, "bar".asBytes)
    doAssert dh.filled == "foobar".len+32
    doAssert dh.pop() == initHpackBound(
      0 ..< "foo".len,
      "foo".len .. "foobar".len-1
    )
    doAssert dh.filled == 0
  block:
    var dh = initHpack(256)
    var s = newString(256-32)
    for i in 0 .. s.len-1:
      s[i] = 'a'
    dh.add(s.asBytes, "".asBytes)
    doAssert dh.filled == 256
    discard dh.pop()
    doAssert dh.filled == 0
    dh.add(s.asBytes, "".asBytes)
    dh.add("a".asBytes, "bc".asBytes)
    doAssert dh.filled == "abc".len+32
  block:
    var dh = initHpack(256)
    dh.add("a".asBytes, "bc".asBytes)
    dh.add("a".asBytes, "bc".asBytes)
    doAssert dh.filled == ("abc".len+32)*2
    discard dh.pop()
    doAssert dh.filled == "abc".len+32
    discard dh.pop()
    doAssert dh.filled == 0
  block:
    echo "Test Hpack length"
    var dh = initHpack(1024)
    dh.add("foo".asBytes, "bar".asBytes)
    doAssert dh.len == 1
    discard dh.pop()
    doAssert dh.len == 0
    for _ in 0 ..< 4:
      dh.add("a".asBytes, "bc".asBytes)
    doAssert dh.len == 4
    for _ in 0 ..< 4:
      discard dh.pop()
    doAssert dh.len == 0
  block:
    echo "Test Hpack strsize"
    var dh = initHpack(76)
    dh.add("asd".asBytes, "asd".asBytes)
    doAssert dh.filled == 38
    dh.add("qwe".asBytes, "qwe".asBytes)
    doAssert dh.filled == 76
    doAssert dh.len == 2
    var res = newSeq[byte]()
    dh.substr(res, dh[0].n)
    dh.substr(res, dh[0].v)
    doAssert res.toString == "qweqwe"
    res.setLen 0
    dh.substr(res, dh[1].n)
    dh.substr(res, dh[1].v)
    doAssert res.toString == "asdasd"
    dh.add("a".asBytes, "".asBytes)
    doAssert dh.filled == 71
    doAssert dh.len == 2
    res.setLen 0
    dh.substr(res, dh[0].n)
    dh.substr(res, dh[0].v)
    doAssert res.toString == "a"
    res.setLen 0
    dh.substr(res, dh[1].n)
    dh.substr(res, dh[1].v)
    doAssert res.toString == "qweqwe"
  block:
    echo "Test Hpack resize"
    var dh = initHpack(256)
    dh.add("asd".asBytes, "asd".asBytes)
    dh.add("qwe".asBytes, "qwe".asBytes)
    dh.add("zxc".asBytes, "zxc".asBytes)
    doAssert dh.len == 3
    dh.setSize(100)
    doAssert dh.len == 2
    doAssert $dh ==
      "zxc: zxc\r\L" &
      "qwe: qwe\r\L"
    dh.setSize(0)
    doAssert dh.len == 0
    dh.add("zxc".asBytes, "zxc".asBytes)
    doAssert dh.len == 0
    dh.setSize(256)
    doAssert dh.len == 0
  block:
    # test for out of bounds wrap around bug
    echo "Test Hpack shrink"
    var dh = initHpack(500)
    for _ in 0 .. 200:
      dh.add("asd".asBytes, "qwe".asBytes)
    dh.setSize(100)
    doAssert $dh ==
      "asd: qwe\r\L" &
      "asd: qwe\r\L"
  block:
    # test for wrap around bug
    echo "Test Hpack grow"
    var dh = initHpack(123)
    for _ in 0 .. 63:
      dh.add("zxc".asBytes, "asdqw".asBytes)
    dh.setSize(234)
    #echo $dh
    doAssert $dh ==
      "zxc: asdqw\r\L" &
      "zxc: asdqw\r\L" &
      "zxc: asdqw\r\L"
  block:
    echo "Test Hpack grow 2"
    var dh = initHpack(123)
    for _ in 0 .. 63:
      dh.add("zxc".asBytes, "asdqw".asBytes)
    dh.setSize(256)
    #echo $dh
    doAssert $dh ==
      "zxc: asdqw\r\L" &
      "zxc: asdqw\r\L" &
      "zxc: asdqw\r\L"
  block:
    echo "Test Hpack grow 3"
    var dh = initHpack(123)
    for _ in 0 .. 63:
      dh.add("zxc".asBytes, "asdqw".asBytes)
    dh.setSize(124)
    #echo $dh
    doAssert $dh ==
      "zxc: asdqw\r\L" &
      "zxc: asdqw\r\L" &
      "zxc: asdqw\r\L"
  block:
    echo "Test Hpack grow 4"
    var dh = initHpack(123)
    dh.add("zxc".asBytes, "asdqw".asBytes)
    dh.setSize(234)
    #echo $dh
    doAssert $dh ==
      "zxc: asdqw\r\L"
  block:
    echo "Test Hpack empty name at 0"
    var dh = initHpack(256)
    dh.add("".asBytes, "x".asBytes)
    doAssert dh.filled == 1+32
    doAssert dh[0] == initHpackBound(0 .. -1, 0 .. 0)
    doAssert $dh == ": x\r\L"
  block:
    echo "Test Hpack empty value at 0"
    var a, b = newString(32)
    for i in 0 .. a.len-1:
      a[i] = 'a'
      b[i] = 'b'
    var dh = initHpack(64)
    dh.add(a.asBytes, "".asBytes)
    # evicts the first entry; the name ends
    # at the end of the buffer, so the value is at 0
    dh.add(b.asBytes, "".asBytes)
    doAssert dh.len == 1
    doAssert dh[0] == initHpackBound(32 .. 63, 0 .. -1)
    doAssert $dh == b & ": \r\L"
