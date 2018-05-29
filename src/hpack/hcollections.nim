## Dynamic headers table

from math import isPowerOfTwo

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

type
  HBounds* = object
    ## Name and value boundaries
    n*, v*: Slice[int]

proc initHBounds*(n, v: Slice[int]): HBounds =
  HBounds(n: n, v: v)

type
  DynHeaders* = object
    ## A circular queue.
    ## This is an implementaion of the
    ## dynamic header table. It has both
    ## total length of headers and
    ## number of headers limits.
    ## It can be efficiently reused
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
  ## Both string size and queue size
  ## must be a power of two.
  assert strsize > 32 and strsize.isPowerOfTwo
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
  q.length

proc reset*(q: var DynHeaders) {.inline.} =
  q.head = q.b.len-1
  q.pos = 0
  q.filled = 0
  q.tail = 0
  q.length = 0

proc `[]`*(q: DynHeaders, i: Natural): HBounds {.inline.} =
  assert i < q.len, "out of bounds"
  q.b[(q.tail+q.len-1-i) and (q.b.len-1)]

template a(hb: HBounds): int =
  hb.n.a

template b(hb: HBounds): int =
  hb.v.b

proc left(q: DynHeaders): int {.inline.} =
  ## Return available space
  assert q.filled <= q.s.len
  q.s.len-q.filled

proc pop(q: var DynHeaders): HBounds {.inline.} =
  assert q.len > 0, "empty queue"
  result = q.b[q.tail]
  q.tail = (q.tail+1) and (q.b.len-1)
  dec q.length
  dec(q.filled, result.b-result.a+1+32)
  assert q.filled >= 0

proc add*(q: var DynHeaders, h, v: openArray[char]) {.inline.} =
  let hvLen = v.len + h.len
  while q.len > 0 and hvLen > q.left-32:
    discard q.pop()
  if hvLen > q.s.len-32:
    raise newException(ValueError, "string too long")
  q.head = (q.head+1) and (q.b.len-1)
  q.b[q.head] = HBounds(
    n: q.pos .. q.pos+h.len-1,
    v: q.pos+h.len .. q.pos+hvLen-1)
  q.length = min(q.b.len, q.length+1)
  let nLen = min(h.len, q.s.len-q.pos)
  strcopy(q.s, h, q.pos, 0, nLen)
  strcopy(q.s, h, 0, nLen, h.len-nLen)
  q.pos = (q.pos+h.len) and (q.s.len-1)
  let vLen = min(v.len, q.s.len-q.pos)
  strcopy(q.s, v, q.pos, 0, vLen)
  strcopy(q.s, v, 0, vLen, v.len-vLen)
  q.pos = (q.pos+v.len) and (q.s.len-1)
  inc(q.filled, hvLen+32)
  assert q.filled <= q.s.len

# todo: remove?
proc add*(q: var DynHeaders, hv: openArray[char], b: int) {.inline.} =
  assert b < hv.len
  q.add(toOpenArray(hv, 0, b-1), toOpenArray(hv, b, hv.len-1))

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
  assert hb.b >= hb.a
  let sLen = s.len
  let bLen = hb.b-hb.a+1
  s.setLen(sLen+bLen)
  let mLen = min(bLen, q.s.len-hb.a)
  strcopy(s, q.s, sLen, hb.a, mLen)
  strcopy(s, q.s, sLen+mLen, 0, bLen-mLen)

proc `$`*(q: DynHeaders): string {.inline.} =
  ## Use it for debugging purposes only
  result = ""
  for hb in q:
    q.substr(result, initHBounds(hb.n, hb.n))
    result.add(": ")
    q.substr(result, initHBounds(hb.v, hb.v))
    result.add("\r\L")

proc toStr(s: openArray[char]): string =
  result = ""
  for c in s:
    result.add(c)

proc cmp*(q: DynHeaders, b: Slice[int], s: openArray[char]): bool {.inline.} =
  ## Compare a header or value against a string
  result = true
  if b.len != s.len:
    return false
  let mLen = min(q.s.len, b.b+1)
  var
    i = 0
    j = b.a
  while j < mLen:
    if s[i] != q.s[j]:
      return false
    inc i
    inc j
  j = 0
  while i < s.len:
    if s[i] != q.s[j]:
      return false
    inc i
    inc j

when isMainModule:
  block:
    echo "Test DynHeaders"
    var dh = initDynHeaders(256, 16)
    dh.add("cache-controlprivate", "cache-control".len)
    dh.add("dateMon, 21 Oct 2013 20:13:21 GMT", "date".len)
    dh.add("locationhttps://www.example.com", "location".len)
    dh.add(":status307", ":status".len)
    doAssert($dh ==
      ":status: 307\r\L" &
      "location: https://www.example.com\r\L" &
      "date: Mon, 21 Oct 2013 20:13:21 GMT\r\L" &
      "cache-control: private\r\L")
    dh.add("dateMon, 21 Oct 2013 20:13:22 GMT", "date".len)
    dh.add("content-encodinggzip", "content-encoding".len)
    dh.add("set-cookiefoo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; " &
      "max-age=3600; version=1", "set-cookie".len)
    doAssert($dh ==
      "set-cookie: foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; " &
      "max-age=3600; version=1\r\L" &
      "content-encoding: gzip\r\L" &
      "date: Mon, 21 Oct 2013 20:13:22 GMT\r\L")
  block:
    echo "Test DynHeaders filled"
    var dh = initDynHeaders(256, 16)
    dh.add("foobar", "foo".len)
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
    dh.add(s, 1)
    doAssert dh.filled == 256
    discard dh.pop()
    doAssert dh.filled == 0
    dh.add(s, 1)
    dh.add("abc", 1)
    doAssert dh.filled == "abc".len+32
  block:
    var dh = initDynHeaders(256, 16)
    dh.add("abc", 1)
    dh.add("abc", 1)
    doAssert dh.filled == ("abc".len+32)*2
    discard dh.pop()
    doAssert dh.filled == "abc".len+32
    discard dh.pop()
    doAssert dh.filled == 0
  block:
    echo "Test DynHeaders length"
    var dh = initDynHeaders(1024, 4)
    dh.add("foobar", "foo".len)
    doAssert dh.length == 1
    discard dh.pop()
    doAssert dh.length == 0
    for _ in 0 ..< 4:
      dh.add("abc", 1)
    doAssert dh.length == 4
    dh.add("abc", 1)
    doAssert dh.length == 4
    for _ in 0 ..< 4:
      discard dh.pop()
    doAssert dh.length == 0
