## Dynamic headers table

import std/deques
import ./exceptions

export
  exceptions

type
  DynHeadersError* = object of HpackError

# XXX stdlib add(string, openArray[char]) is missing
func strcopy(
  x: var string,
  y: openArray[char],
  xi, yi, xyLen: int
) {.inline, raises: [].} =
  var
    i = 0
    j = xi
    k = yi
  while i < xyLen:
    x[j] = y[k]
    inc i
    inc j
    inc k

func strcmp(
  x, y: openArray[char],
  xi, yi, xyLen: Natural
): bool {.inline, raises: [].} =
  x.toOpenArray(xi, xi+xyLen-1) == y.toOpenArray(yi, yi+xyLen-1)

type
  HBounds* = object
    ## Header's name and value boundaries
    n*, v*: Slice[int]

func initHBounds*(n, v: Slice[int]): HBounds {.inline.} =
  ## Initialize ``HBounds`` with
  ## header's name and value
  HBounds(n: n, v: v)

type
  DynHeaders* = object
    ## A circular queue.
    ## This is an implementaion of the
    ## dynamic header table.
    ## It can be efficiently reused.
    ## ``HBounds`` ends may be out of bounds and
    ## need to be wrapped around. All
    ## functions here take care of that
    s: string
    pos, filled: int
    bounds: Deque[HBounds]
    size, maxSize*, initialSize, minSetSize: int

func initDynHeaders*(strsize: int): DynHeaders {.inline.} =
  ## Initialize a dynamic headers table.
  ## ``strsize`` is the max size in bytes
  ## of all headers put together.
  DynHeaders(
    s: newString(strsize),
    pos: 0,
    filled: 0,
    bounds: initDeque[HBounds](0),
    size: strsize,
    maxSize: strsize,
    initialSize: strsize,
    minSetSize: strsize
  )

func len*(q: DynHeaders): int {.inline, raises: [].} =
  q.bounds.len

func clear*(q: var DynHeaders) {.inline, raises: [].} =
  ## Efficiently clear the table
  q.pos = 0
  q.filled = 0
  q.bounds.clear()
  q.minSetSize = 0

func reset*(q: var DynHeaders) {.deprecated.} =
  ## Deprecated, use ``clear()`` instead
  q.clear()

func `[]`*(q: DynHeaders, i: Natural): HBounds {.inline, raises: [].} =
  q.bounds[i]

template len(hb: HBounds): int =
  hb.n.len+hb.v.len

func left(q: DynHeaders): Natural {.inline, raises: [].} =
  ## Return available space
  q.size-q.filled

func pop(q: var DynHeaders): HBounds {.inline, raises: [].} =
  ## Return and remove header
  ## from the table in FIFO order
  doAssert q.len > 0, "empty queue"
  result = q.bounds.popLast()
  dec(q.filled, result.len+32)
  doAssert q.filled >= 0

func add*(q: var DynHeaders, n, v: openArray[char]) {.raises: [].} =
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
  q.bounds.addFirst HBounds(n: hbn, v: hbv)
  inc(q.filled, nvLen+32)
  doAssert q.filled <= q.size

func setSize*(q: var DynHeaders, strsize: Natural) {.raises: [].} =
  ## Resize the total headers max length.
  ## Evicts entries that don't fit anymore.
  ## Set to ``0`` to clear it.
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
  for b in q.bounds:
    yield b

iterator pairs*(q: DynHeaders): (int, HBounds) {.inline, raises: [].} =
  for i, b in pairs q.bounds:
    yield (i, b)

func substr*(q: DynHeaders, s: var string, x: Slice[int]) {.raises: [].} =
  doAssert x.b+1 >= x.a
  let sLen = s.len
  let bLen = x.len
  s.setLen(sLen+bLen)
  let mLen = min(bLen, q.s.len-x.a)
  strcopy(s, q.s, sLen, x.a, mLen)
  strcopy(s, q.s, sLen+mLen, 0, bLen-mLen)

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
  b: Slice[int],
  s: openArray[char]
): bool {.raises: [].} =
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
      "foo".len .. "foobar".len-1)
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
