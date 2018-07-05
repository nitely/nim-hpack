## Dynamic headers table

from math import isPowerOfTwo

import
  exceptions

export
  exceptions

type
  DynHeadersError* = object of HpackError

template strcopy(x: var string, y: openArray[char], xi, yi, xyLen: int) =
  var
    i = 0
    j = xi
    k = yi
  while i < xyLen:
    x[j] = y[k]
    inc i
    inc j
    inc k

proc strcmp(
    x, y: openArray[char],
    xi, yi, xyLen: Natural): bool {.inline.} =
  result = true
  var
    i = 0
    j = xi
    k = yi
  while i < xyLen:
    if x[j] != y[k]:
      return false
    inc i
    inc j
    inc k

type
  HBounds* = object
    ## Header's name and value boundaries
    n*, v*: Slice[int]

proc initHBounds*(n, v: Slice[int]): HBounds {.inline.} =
  ## Initialize ``HBounds`` with
  ## header's name and value
  HBounds(n: n, v: v)

# todo: HPACK does not know about the qsize limit,
#       so raise an exception when there is no more room available
type
  DynHeaders* = object
    ## A circular queue.
    ## This is an implementaion of the
    ## dynamic header table. It has both
    ## total length of headers and
    ## number of headers limits.
    ## It can be efficiently reused.
    ## ``HBounds`` ends may be out of bounds and
    ## need to be wrapped around. All
    ## functions here take care of that
    s: string
    pos, filled: int
    b: seq[HBounds]
    head, tail, length: int

proc initDynHeaders*(strsize, qsize: Natural): DynHeaders {.inline.} =
  ## Initialize a dynamic headers table.
  ## ``strsize`` is the max size in bytes
  ## of all headers put together.
  ## It must be greater than 32,
  ## since each header has 32 bytes
  ## of overhead according to spec.
  ## Queue size must be a power of two.
  assert strsize > 32
  assert qsize.isPowerOfTwo
  DynHeaders(
    s: newString(strsize),
    pos: 0,
    filled: 0,
    b: newSeq[HBounds](qsize),
    head: qsize-1,
    tail: 0,
    length: 0)

proc len*(q: DynHeaders): int {.inline.} =
  ## Number of headers
  q.length

proc clear*(q: var DynHeaders) {.inline.} =
  ## Efficiently clear the table
  q.head = q.b.len-1
  q.pos = 0
  q.filled = 0
  q.tail = 0
  q.length = 0

proc reset*(q: var DynHeaders) {.deprecated.} =
  ## Deprecated, use ``clear()`` instead
  q.clear()

proc `[]`*(q: DynHeaders, i: Natural): HBounds {.inline.} =
  ## Return header bounds at position ``i``
  assert i < q.len, "out of bounds"
  q.b[(q.tail+q.len-1-i) and (q.b.len-1)]

template a(hb: HBounds): int =
  hb.n.a

template b(hb: HBounds): int =
  hb.v.b

proc left(q: DynHeaders): Natural {.inline.} =
  ## Return available space
  q.s.len-q.filled

proc pop(q: var DynHeaders): HBounds {.inline.} =
  ## Return and remove header
  ## from the table in FIFO order
  assert q.len > 0, "empty queue"
  result = q.b[q.tail]
  q.tail = (q.tail+1) and (q.b.len-1)
  dec q.length
  dec(q.filled, result.b-result.a+1+32)
  assert q.filled >= 0

proc add*(q: var DynHeaders, n, v: openArray[char]) {.inline.} =
  ## Add a header name and value to the table.
  ## Evicts entries that no longer fit.
  ## Items are added and removed in FIFO order
  let nvLen = v.len + n.len
  while q.len > 0 and nvLen > q.left-32:
    discard q.pop()
  if nvLen > q.s.len-32:
    raise newException(DynHeadersError, "string too long")
  q.head = (q.head+1) and (q.b.len-1)
  q.b[q.head] = HBounds(
    n: q.pos .. q.pos+n.len-1,
    v: q.pos+n.len .. q.pos+nvLen-1)
  q.length = min(q.b.len, q.length+1)
  let nLen = min(n.len, q.s.len-q.pos)
  strcopy(q.s, n, q.pos, 0, nLen)
  strcopy(q.s, n, 0, nLen, n.len-nLen)
  q.pos = (q.pos+n.len) mod q.s.len
  let vLen = min(v.len, q.s.len-q.pos)
  strcopy(q.s, v, q.pos, 0, vLen)
  strcopy(q.s, v, 0, vLen, v.len-vLen)
  q.pos = (q.pos+v.len) mod q.s.len
  inc(q.filled, nvLen+32)
  assert q.filled <= q.s.len

proc resize*(q: var DynHeaders, strsize: Natural) {.inline.} =
  ## Resize the total headers max length.
  ## Evicts entries that don't fit anymore.
  ## Set to ``0`` to clear the queue.
  q.s.setLen(strsize)
  while strsize < q.filled:
    discard q.pop()

iterator items*(q: DynHeaders): HBounds {.inline.} =
  ## Yield headers in FIFO order
  var i = 0
  let head = q.tail+q.len-1
  while i < q.len:
    yield q.b[(head-i) and (q.b.len-1)]
    inc i

iterator pairs*(q: DynHeaders): (int, HBounds) {.inline.} =
  ## Yield headers in FIFO order
  var i = 0
  let head = q.tail+q.len-1
  while i < q.len:
    yield (i, q.b[(head-i) and (q.b.len-1)])
    inc i

proc substr*(q: DynHeaders, s: var string, hb: HBounds) {.inline.} =
  ## Append a header name and value to ``s``
  assert hb.b+1 >= hb.a
  let sLen = s.len
  let bLen = hb.b-hb.a+1
  s.setLen(sLen+bLen)
  let mLen = min(bLen, q.s.len-hb.a)
  strcopy(s, q.s, sLen, hb.a, mLen)
  strcopy(s, q.s, sLen+mLen, 0, bLen-mLen)

proc `$`*(q: DynHeaders): string {.inline.} =
  ## Use it for debugging purposes only.
  ## Use ``substr`` and ``cmp`` for anything else
  result = ""
  for hb in q:
    q.substr(result, initHBounds(hb.n, hb.n))
    result.add(": ")
    q.substr(result, initHBounds(hb.v, hb.v))
    result.add("\r\L")

proc cmp*(
    q: DynHeaders,
    b: Slice[int],
    s: openArray[char]): bool {.inline.} =
  ## Efficiently compare a header name
  ## or value against a string
  if b.len != s.len:
    return false
  let mLen = min(b.len, q.s.len-b.a)
  result =
    strcmp(s, q.s, 0, b.a, mLen) and
    strcmp(s, q.s, mLen, 0, b.len-mLen)

when isMainModule:
  block:
    echo "Test DynHeaders"
    var dh = initDynHeaders(256, 16)
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
    echo $dh
    doAssert($dh ==
      "set-cookie: foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; " &
      "max-age=3600; version=1\r\L" &
      "content-encoding: gzip\r\L" &
      "date: Mon, 21 Oct 2013 20:13:22 GMT\r\L")
  block:
    echo "Test DynHeaders filled"
    var dh = initDynHeaders(256, 16)
    dh.add("foo", "bar")
    doAssert dh.filled == "foobar".len+32
    doAssert dh.pop() == initHBounds(
      0 ..< "foo".len,
      "foo".len .. "foobar".len-1)
    doAssert dh.filled == 0
  block:
    var dh = initDynHeaders(256, 16)
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
    var dh = initDynHeaders(256, 16)
    dh.add("a", "bc")
    dh.add("a", "bc")
    doAssert dh.filled == ("abc".len+32)*2
    discard dh.pop()
    doAssert dh.filled == "abc".len+32
    discard dh.pop()
    doAssert dh.filled == 0
  block:
    echo "Test DynHeaders length"
    var dh = initDynHeaders(1024, 4)
    dh.add("foo", "bar")
    doAssert dh.length == 1
    discard dh.pop()
    doAssert dh.length == 0
    for _ in 0 ..< 4:
      dh.add("a", "bc")
    doAssert dh.length == 4
    dh.add("a", "bc")
    doAssert dh.length == 4
    for _ in 0 ..< 4:
      discard dh.pop()
  block:
    echo "Test DynHeaders strsize"
    var dh = initDynHeaders(76, 8)
    dh.add("asd", "asd")
    doAssert dh.filled == 38
    dh.add("qwe", "qwe")
    doAssert dh.filled == 76
    doAssert dh.len == 2
    var res = ""
    dh.substr(res, dh[0])
    doAssert res == "qweqwe"
    res = ""
    dh.substr(res, dh[1])
    doAssert res == "asdasd"
    dh.add("a", "")
    doAssert dh.filled == 71
    doAssert dh.len == 2
    res = ""
    dh.substr(res, dh[0])
    doAssert res == "a"
    res = ""
    dh.substr(res, dh[1])
    doAssert res == "qweqwe"
  block:
    echo "Test DynHeaders resize"
    var dh = initDynHeaders(256, 16)
    dh.add("asd", "asd")
    dh.add("qwe", "qwe")
    dh.add("zxc", "zxc")
    doAssert dh.len == 3
    dh.resize(100)
    doAssert dh.len == 2
    doAssert $dh ==
      "zxc: zxc\r\L" &
      "qwe: qwe\r\L"
    dh.resize(0)
    doAssert dh.len == 0
    dh.resize(256)
    doAssert dh.len == 0
