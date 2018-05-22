## HPACK decoder

from math import isPowerOfTwo

import huffman_decoder
import headers_data

type
  DecodeError = object of ValueError

template raiseDecodeError(msg: string) =
  raise newException(DecodeError, msg)

proc intdecode(s: openArray[byte], n: int, d: var int): int =
  ## Return number of consumed octets.
  ## ``n`` param is the N-bit prefix.
  ## Decoded int is assigned to ``d``
  assert n in {1 .. 8}
  assert len(s) > 0
  d = 1 shl n - 1
  result = 1
  if (s[0].int and d) < d:
    d = s[0].int and d
    return
  var
    cb = 1 shl 7
    sf = int.high
    b, m = 0
  # MSB == 1 means the value
  # continues in next byte
  while cb shr 7 == 1 and result < len(s):
    cb = s[result].int
    b = cb and 0x7f
    if b > sf:
      raiseDecodeError("overflow")
    b = b shl m
    if d > int.high-b:
      raiseDecodeError("overflow")
    inc(d, b)
    inc(m, 7)
    sf = sf shr 7
    inc result
  if cb shr 7 == 1:
    raiseDecodeError("continuation byte without continuation")

# todo: add neverIndex flag?
type
  DecodedSlice* = object
    ## A decoded string slice.
    ## It has the boundaries of
    ## header name and value
    n*: Slice[int]
    v*: Slice[int]
  DecodedStr* = object
    ## A decoded string contains
    ## a string of all header/value
    ## put together and a
    ## sequence of their boundaries
    s*: string
    b*: seq[int]

proc initDecodedStr*(): DecodedStr {.inline.} =
  DecodedStr(s: "", b: @[])

proc len*(d: DecodedStr): int {.inline.} =
  assert d.b.len mod 2 == 0
  d.b.len div 2

proc `[]`*(d: DecodedStr, i: int): DecodedSlice {.inline.} =
  assert i.int < d.len, "out of bounds"
  let ix = i.int*2
  result.n.a = if ix == 0: 0 else: d.b[ix-1]
  result.n.b = d.b[ix]-1
  result.v.a = d.b[ix]
  result.v.b = d.b[ix+1]-1

proc `[]`*(d: DecodedStr, i: BackwardsIndex): DecodedSlice {.inline.} =
  assert i.int <= d.len, "out of bounds"
  let ix = i.int*2
  result.n.a = if ix == d.b.len: 0 else: d.b[^(ix+1)]
  result.n.b = d.b[^ix]-1
  result.v.a = d.b[^ix]
  result.v.b = d.b[^(ix-1)]-1

proc reset*(d: var DecodedStr) {.inline.} =
  d.s.setLen(0)
  d.b.setLen(0)

proc add*(d: var DecodedStr, s: string) {.inline.} =
  ## Add either a header name or a value.
  ##
  ## .. code-block:: nim
  ##   var ds = initDecodedStr()
  ##   ds.add("my-header")
  ##   ds.add("my-value")
  ##
  d.s.add(s)
  d.b.add(d.s.len)

iterator items*(d: DecodedStr): DecodedSlice {.inline.} =
  ## Iterate over header names and values
  ##
  ## .. code-block:: nim
  ##   var
  ##     i = 0
  ##     ds = initDecodedStr()
  ##   ds.add("my-header")
  ##   ds.add("my-value")
  ##   for h in ds:
  ##     assert ds.s[h.n] == "my-header"
  ##     assert ds.s[h.v] == "my-value"
  ##     inc i
  ##   assert i == 1
  ##
  assert d.b.len mod 2 == 0
  var i, j = 0
  while j < d.b.len:
    yield d[i]
    inc i
    inc(j, 2)

proc strdecode(s: openArray[byte], d: var DecodedStr): int =
  ## Decode a literal string.
  ## Return number of consumed octets.
  ## Decoded string is appended to ``d``.
  assert len(s) > 0
  let n = intdecode(s, 7, result)
  if result > int.high-n:
    raiseDecodeError("overflow")
  inc(result, n)
  if result > s.len:
    raiseDecodeError("out of bounds")
  if s[0] shr 7 == 1:  # huffman encoded
    if hcdecode(toOpenArray(s, n, result-1), d.s) == -1:
      raiseDecodeError("huffman error")
    d.b.add(d.s.len)
  else:
    # todo: memcopy
    let j = d.s.len
    d.s.setLen(d.s.len + result-n)
    for i in 0 ..< result-n:
      d.s[j+i] = s[n+i].char
    d.b.add(d.s.len)

type
  HBounds = object
    ## Name and value boundaries
    n, v: Slice[int]

proc initHBounds(n, v: Slice[int]): HBounds =
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

proc `[]`(q: DynHeaders, i: Natural): HBounds {.inline.} =
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

proc add(q: var DynHeaders, x: openArray[char], b: int) {.inline.} =
  assert b < x.len
  while q.len > 0 and x.len > q.left-32:
    discard q.pop()
  if x.len > q.s.len-32:
    raise newException(ValueError, "string too long")
  q.head = (q.head+1) and (q.b.len-1)
  q.b[q.head] = HBounds(
    n: q.pos ..< q.pos+b,
    v: q.pos+b .. q.pos+x.len-1)
  q.length = min(q.b.len, q.length+1)
  for c in x:
    q.s[q.pos] = c
    q.pos = (q.pos+1) and (q.s.len-1)
  inc(q.filled, x.len+32)
  assert q.filled <= q.s.len

iterator items(q: DynHeaders): HBounds {.inline.} =
  ## Yield headers in FIFO order
  var i = 0
  let head = q.tail+q.len-1
  while i < q.len:
    yield q.b[(head-i) and (q.b.len-1)]
    inc i

proc substr(q: DynHeaders, s: var string, hb: HBounds) {.inline.} =
  assert hb.b >= hb.a
  let o = s.len
  s.setLen(s.len+hb.b-hb.a+1)
  for i in hb.a .. hb.b:
    s[o+i-hb.a] = q.s[i and (q.s.len-1)]

proc addIn(dh: DynHeaders, d: var DecodedStr, i: int) {.inline.} =
  let hb = dh[i]
  dh.substr(d.s, hb)
  d.b.add(d.s.len-(hb.v.b-hb.v.a+1))
  d.b.add(d.s.len)

proc addNameIn(dh: DynHeaders, d: var DecodedStr, i: int) {.inline.} =
  let hb = dh[i]
  dh.substr(d.s, initHBounds(hb.n, hb.n))
  d.b.add(d.s.len)

proc `$`*(dh: DynHeaders): string {.inline.} =
  ## Use it for debugging purposes only
  result = ""
  for hb in dh:
    dh.substr(result, initHBounds(hb.n, hb.n))
    result.add(": ")
    dh.substr(result, initHBounds(hb.v, hb.v))
    result.add("\r\L")

proc hname(h: DynHeaders, d: var DecodedStr, i: int) =
  assert i > 0
  let
    i = i-1
    idyn = i-headersTable.len
  if i < len(headersTable):
    d.add(headersTable[i][0])
  elif idyn < h.len:
    h.addNameIn(d, idyn)
  else:
    raiseDecodeError("dyn header name not found")

proc header(h: DynHeaders, d: var DecodedStr, i: int) =
  assert i > 0
  let
    i = i-1
    idyn = i-headersTable.len
  if i < headersTable.len:
    d.add(headersTable[i][0])
    d.add(headersTable[i][1])
  elif idyn < h.len:
    h.addIn(d, idyn)
  else:
    raiseDecodeError("dyn header not found")

proc litdecode(
    s: openArray[byte],
    h: var DynHeaders,
    d: var DecodedStr,
    np: int,
    store: static[bool]): int =
  ## Decode literal header field:
  ## with incremental indexing,
  ## without indexing, or
  ## never indexed.
  ## Return number of consumed octets
  var dint = 0
  result = intdecode(s, np, dint)
  if dint > 0:
    hname(h, d, dint)
  else:
    if result > s.len-1:
      raiseDecodeError("out of bounds")
    let nh = strdecode(toOpenArray(s, result, s.len-1), d)
    if result > int.high-nh:
      raiseDecodeError("overflow")
    inc(result, nh)
  if result > s.len-1:
    raiseDecodeError("out of bounds")
  let nv = strdecode(toOpenArray(s, result, s.len-1), d)
  if result > int.high-nv:
    raiseDecodeError("overflow")
  inc(result, nv)
  when store:
    let hsl = d[^1]
    h.add(
      toOpenArray(d.s, hsl.n.a, hsl.v.b),
      hsl.n.b-hsl.n.a+1)

proc hdecode*(s: openArray[byte], h: var DynHeaders, d: var DecodedStr): int =
  ## Decode a single header.
  ## Return number of consumed octets.
  ## ``s`` bytes sequence must not be empty.
  assert len(s) > 0
  # indexed
  if s[0] shr 7 == 1:
    var dint = 0
    result = intdecode(s, 7, dint)
    if dint == 0:
      raiseDecodeError("invalid header index 0")
    header(h, d, dint)
    return
  # incremental indexing
  if s[0] shr 6 == 1:
    # todo: save header name into dyn table when not in static
    result = litdecode(s, h, d, 6, true)
    return
  # without indexing or
  # never indexed
  if s[0] shr 4 <= 1:
    result = litdecode(s, h, d, 4, false)
    return
  raiseDecodeError("unknown octet prefix")

proc hdecodeAll*(
    s: openArray[byte],
    h: var DynHeaders,
    d: var DecodedStr) =
  ## Decode all headers from the blob of bytes
  ## ``s`` and stores it into a decoded string``d``.
  ## The dynamic headers are stored into ``h``
  ## to decode the next message.
  var i = 0
  while i < s.len:
    inc(i, hdecode(toOpenArray(s, i, s.len-1), h, d))
  assert i == s.len

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

  block:
    echo "Test decodedStr"
    var
      i = 0
      ds = initDecodedStr()
    ds.add("my-header")
    ds.add("my-value")
    for h in ds:
      doAssert ds.s[h.n] == "my-header"
      doAssert ds.s[h.v] == "my-value"
      inc i
    assert i == 1
  block:
    let
      h = "foo-header"
      v = "foo-value"
    var ds = initDecodedStr()
    ds.add(h)
    ds.add(v)
    doAssert ds.s[ds[^1].n] == h
    doAssert ds.s[ds[^1].v] == v
    let
      h2 = "bar-header"
      v2 = "bar-value"
    ds.add(h2)
    ds.add(v2)
    doAssert ds.s[ds[^1].n] == h2
    doAssert ds.s[ds[^1].v] == v2
    doAssert ds.s[ds[^2].n] == h
    doAssert ds.s[ds[^2].v] == v

  block:
    echo "Test Encoding 10 Using a 5-Bit Prefix"
    var
      ic = @[byte 0b01010]
      d = 0
    doAssert(intdecode(ic, 5, d) == 1)
    doAssert(d == 10)
  block:
    echo "Test Encoding 1337 Using a 5-Bit Prefix"
    var
      ic = @[byte 0b00011111, 0b10011010, 0b00001010]
      d = 0
    doAssert(intdecode(ic, 5, d) == 3)
    doAssert(d == 1337)
  block:
    echo "Test Encoding 42 Starting at an Octet Boundary"
    var
      ic = @[byte 0b00101010]
      d = 0
    doAssert(intdecode(ic, 8, d) == 1)
    doAssert(d == 42)
  block:
    echo "Test Bad lit int with continuation at the end"
    var
      ic = @[byte 0b00011111, 0b10011010]
      d = 0
    doAssertRaises(DecodeError):
      discard intdecode(ic, 5, d)
  block:
    echo "Test Long lit int32"
    var
      ic = @[
        byte 0b11111111, 0b11111111,
        0b11111111, 0b01111111]
      d = 0
    doAssert(intdecode(ic, 8, d) == 4)
    doAssert(d == 2097406)
  block:
    echo "Test Way too long lit int"
    var
      ic = @[
        byte 0b11111111, 0b11111111,
        0b11111111, 0b11111111,
        0b11111111, 0b11111111,
        0b11111111, 0b11111111,
        0b11111111, 0b01111111]
      d = 0
    doAssertRaises(DecodeError):
      discard intdecode(ic, 8, d)
  block:
    echo "Test Bad lit int with too many zeros in the middle"
    var ic = @[byte 0b11111111]
    for _ in 0 ..< 123:  # add zeroes
      ic.add(0b10000000)
    ic.add(0b01111111)
    var d = 0
    doAssertRaises(DecodeError):
      discard intdecode(ic, 8, d)
  block:
    echo "Test Lit int with too many starting zeros"
    var ic = @[byte 0b11111111]
    for _ in 0 ..< 1234:  # add zeroes
      ic.add(0b10000000)
    ic.add(0b0)
    var d = 0
    doAssert(intdecode(ic, 8, d) == 1236)
    doAssert(d == 255)

  block:
    echo "Test Literal Header Field"
    var
      ic = @[
        byte 0b00001010, 0b01100011,
        0b01110101, 0b01110011,
        0b01110100, 0b01101111,
        0b01101101, 0b00101101,
        0b01101011, 0b01100101,
        0b01111001]
      d = initDecodedStr()
    doAssert(strdecode(ic, d) == ic.len)
    doAssert(d.s == "custom-key")
  block:
    var
      ic = @[
        byte 0b00001101, 0b01100011,
        0b01110101, 0b01110011,
        0b01110100, 0b01101111,
        0b01101101, 0b00101101,
        0b01101000, 0b01100101,
        0b01100001, 0b01100100,
        0b01100101, 0b01110010]
      d = initDecodedStr()
    doAssert(strdecode(ic, d) == ic.len)
    doAssert(d.s == "custom-header")
  block:
    var
      ic = @[
        byte 0b00001100, 0b00101111,
        0b01110011, 0b01100001,
        0b01101101, 0b01110000,
        0b01101100, 0b01100101,
        0b00101111, 0b01110000,
        0b01100001, 0b01110100,
        0b01101000]
      d = initDecodedStr()
    doAssert(strdecode(ic, d) == ic.len)
    doAssert(d.s == "/sample/path")
  block:
    var
      ic = @[
        byte 0b00001000, 0b01110000,
        0b01100001, 0b01110011,
        0b01110011, 0b01110111,
        0b01101111, 0b01110010,
        0b01100100]
      d = initDecodedStr()
    doAssert(strdecode(ic, d) == ic.len)
    doAssert(d.s == "password")
  block:
    var
      ic = @[
        byte 0b00000110, 0b01110011,
        0b01100101, 0b01100011,
        0b01110010, 0b01100101,
        0b01110100]
      d = initDecodedStr()
    doAssert(strdecode(ic, d) == ic.len)
    doAssert(d.s == "secret")
  block:
    var
      ic = @[
        byte 0b00001111, 0b01110111,
        0b01110111, 0b01110111,
        0b00101110, 0b01100101,
        0b01111000, 0b01100001,
        0b01101101, 0b01110000,
        0b01101100, 0b01100101,
        0b00101110, 0b01100011,
        0b01101111, 0b01101101]
      d = initDecodedStr()
    doAssert(strdecode(ic, d) == ic.len)
    doAssert(d.s == "www.example.com")
  block:
    var
      ic = @[
        byte 0b00001000, 0b01101110,
        0b01101111, 0b00101101,
        0b01100011, 0b01100001,
        0b01100011, 0b01101000,
        0b01100101]
      d = initDecodedStr()
    doAssert(strdecode(ic, d) == ic.len)
    doAssert(d.s == "no-cache")
  block:
    echo "Test Request Examples with Huffman Coding"
    var
      ic = @[
        byte 0b10001100, 0b11110001,
        0b11100011, 0b11000010,
        0b11100101, 0b11110010,
        0b00111010, 0b01101011,
        0b10100000, 0b10101011,
        0b10010000, 0b11110100,
        0b11111111]
      d = initDecodedStr()
    doAssert(strdecode(ic, d) == ic.len)
    doAssert(d.s == "www.example.com")
