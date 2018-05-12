## WIP, highly un-optimized decoder

import deques

import huffman_decoder
import headers_data

type
  DecodeError = object of ValueError

template raiseDecodeError(msg: string) =
  raise newException(DecodeError, msg)

proc intdecode*(s: openArray[byte], n: int, d: var int): int =
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
  DecodedStr* = object
    ## A decoded string contains
    ## a string of all header/value
    ## joined together and a
    ## sequence of their boundaries
    s*: string
    b*: seq[int]
  DecodedSlice* = tuple
    n: Slice[int]
    v: Slice[int]

proc initDecodedStr*(): DecodedStr =
  DecodedStr(s: "", b: @[])

proc `[]`*(d: DecodedStr, i: int): DecodedSlice {.inline.} =
  assert i.int <= d.b.len div 2
  assert d.b.len mod 2 == 0
  let ix = i.int*2
  result.n.a = if ix == 0: 0 else: d.b[ix-1]
  result.n.b = d.b[ix]-1
  result.v.a = d.b[ix]
  result.v.b = d.b[ix+1]-1

proc `[]`*(d: DecodedStr, i: BackwardsIndex): DecodedSlice {.inline.} =
  assert i.int <= d.b.len div 2
  assert d.b.len mod 2 == 0
  let ix = i.int*2
  result.n.a = if ix == d.b.len: 0 else: d.b[^(ix+1)]
  result.n.b = d.b[^ix]-1
  result.v.a = d.b[^ix]
  result.v.b = d.b[^(ix-1)]-1

proc reset*(d: var DecodedStr) =
  d.s.setLen(0)
  d.b.setLen(0)

proc add*(d: var DecodedStr, s: string) =
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
    let j = d.s.len
    d.s.setLen(d.s.len + result-n)
    for i in 0 ..< result-n:
      d.s[j+i] = s[n+i].char
    d.b.add(d.s.len)

type
  Header = object
    h: string
    b: int

proc len(h: Header): int {.inline.} =
  h.h.len

type
  DynHeaders = object
    ## Headers dynamic list
    d: Deque[Header]
    cap: int
    filled: int

proc initDynHeaders*(cap: Natural): DynHeaders {.inline.} =
  ## Initialize ``DynHeaders``. The ``cap``
  ## is the capacity of the queue in octets.
  ## There is no way to set the number of
  ## headers it can hold.
  assert cap > 32
  DynHeaders(
    d: initDeque[Header](32),
    cap: cap,
    filled: 0)

proc `[]`*(dh: DynHeaders, i: int): Header {.inline.} =
  dh.d[i]

proc len*(dh: DynHeaders): int {.inline.} =
  dh.d.len

proc pop*(dh: var DynHeaders): Header {.inline.} =
  result = dh.d.popLast()
  dec(dh.filled, result.len+32)
  assert dh.filled >= 0

proc add*(dh: var DynHeaders, h: Header) {.inline.} =
  assert dh.filled <= dh.cap
  while dh.len > 0 and h.len > dh.cap-dh.filled-32:
    discard dh.pop()
  if h.len > dh.cap-32:
    raiseDecodeError("header too long")
  dh.d.addFirst(h)
  dh.filled = dh.filled + h.len + 32
  assert dh.filled <= dh.cap

iterator items*(dh: DynHeaders): Header {.inline.} =
  for h in dh.d:
    yield h

proc `$`(dh: DynHeaders): string {.inline.} =
  ## Use it for debugging purposes only
  result = ""
  for h in dh:
    result.add(h.h[0 ..< h.b])
    result.add(": ")
    result.add(h.h[h.b ..< h.h.len])
    result.add("\r\L")

proc hname(h: DynHeaders, d: var DecodedStr, i: int) =
  assert i > 0
  let
    i = i-1
    idyn = i-headersTable.len
  if i < len(headersTable):
    d.add(headersTable[i][0])
    # todo: fixme?
    #d.add("")
  elif idyn < h.len:
    # todo: fixme, no extra copy
    d.add(h[idyn].h[0 ..< h[idyn].b])
    # todo: fixme?
    #d.add("")
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
    # todo: fixme, no extra copy
    d.add(h[idyn].h[0 ..< h[idyn].b])
    d.add(h[idyn].h[h[idyn].b ..< h[idyn].h.len])
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
  result = 0
  var dint = 0
  inc(result, intdecode(s, np, dint))
  if dint > 0:
    hname(h, d, dint)
  else:
    # todo: check 1 < len(s)
    let nh = strdecode(toOpenArray(s, result, s.len-1), d)
    inc(result, nh)
  # todo: check 1+nh < len(s) and does not overflow
  let nv = strdecode(toOpenArray(s, result, s.len-1), d)
  inc(result, nv)
  when store:
    let hsl = d[^1]
    h.add(Header(
      # todo: this makes 2 copies, fix
      h: d.s[hsl.n.a .. hsl.v.b],
      b: hsl.n.b - hsl.n.a + 1))

proc hdecode(s: openArray[byte], h: var DynHeaders, d: var DecodedStr): int =
  ## Decode a header.
  ## Return number of consmed octets
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

when isMainModule:
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

  proc toBytes(s: seq[uint16]): seq[byte] =
    result = newSeqOfCap[byte](len(s) * 2)
    for b in s:
      result.add(byte(b shr 8))
      result.add(byte(b and 0xff))

  echo "Test examples verbatim"
  block:
    echo "Test Literal Header Field with Indexing"
    var
      ic = @[
        0x400a'u16, 0x6375, 0x7374, 0x6f6d,
        0x2d6b, 0x6579, 0x0d63, 0x7573,
        0x746f, 0x6d2d, 0x6865, 0x6164, 0x6572].toBytes
      d = initDecodedStr()
      dh = initDynHeaders(255)
    doAssert(hdecode(ic, dh, d) == ic.len)
    var i = 0
    for h in d:
      doAssert(d.s[h.n] == "custom-key")
      doAssert(d.s[h.v] == "custom-header")
      inc i
    doAssert i == 1
    doAssert dh.len == 1
    doAssert($dh == "custom-key: custom-header\r\L")
  block:
    echo "Test Literal Header Field without Indexing"
    var
      ic = @[
        0x040c'u16, 0x2f73, 0x616d,
        0x706c, 0x652f, 0x7061, 0x7468].toBytes
      d = initDecodedStr()
      dh = initDynHeaders(255)
    doAssert(hdecode(ic, dh, d) == ic.len)
    var i = 0
    for h in d:
      doAssert(d.s[h.n] == ":path")
      doAssert(d.s[h.v] == "/sample/path")
      inc i
    doAssert i == 1
    doAssert dh.len == 0
  block:
    echo "Test Literal Header Field Never Indexed"
    var ic = @[
      0x1008'u16, 0x7061, 0x7373, 0x776f,
      0x7264, 0x0673, 0x6563, 0x7265].toBytes
    ic.add(byte 0x74'u8)
    var
      d = initDecodedStr()
      dh = initDynHeaders(255)
    doAssert(hdecode(ic, dh, d) == ic.len)
    var i = 0
    for h in d:
      doAssert(d.s[h.n] == "password")
      doAssert(d.s[h.v] == "secret")
      inc i
    doAssert i == 1
    doAssert dh.len == 0
  block:
    echo "Test Indexed Header Field"
    var
      ic = @[byte 0x82'u8]
      d = initDecodedStr()
      dh = initDynHeaders(255)
    doAssert(hdecode(ic, dh, d) == ic.len)
    var i = 0
    for h in d:
      doAssert(d.s[h.n] == ":method")
      doAssert(d.s[h.v] == "GET")
      inc i
    doAssert i == 1
    doAssert dh.len == 0

  proc hdecodeAll(
      s: openArray[byte],
      h: var DynHeaders,
      d: var DecodedStr): int =
    result = 0
    while result < s.len:
      inc(result, hdecode(toOpenArray(s, result, s.len-1), h, d))

  block:
    echo "Test Request Examples without Huffman Coding"
    var dh = initDynHeaders(255)
    block:
      echo "Test First Request"
      var
        ic = @[
          0x8286'u16, 0x8441, 0x0f77, 0x7777,
          0x2e65, 0x7861, 0x6d70, 0x6c65,
          0x2e63, 0x6f6d].toBytes
        d = initDecodedStr()
        expected = [
          [":method", "GET"],
          [":scheme", "http"],
          [":path", "/"],
          [":authority", "www.example.com"]]
      doAssert hdecodeAll(ic, dh, d) == ic.len
      var i = 0
      for h in d:
        doAssert(d.s[h.n] == expected[i][0])
        doAssert(d.s[h.v] == expected[i][1])
        inc i
      doAssert i == expected.len
      doAssert dh.len == 1
      doAssert $dh == ":authority: www.example.com\r\L"
    block:
      echo "Test Second Request"
      var
        ic = @[
          0x8286'u16, 0x84be, 0x5808, 0x6e6f,
          0x2d63, 0x6163, 0x6865].toBytes
        d = initDecodedStr()
        expected = [
          [":method", "GET"],
          [":scheme", "http"],
          [":path", "/"],
          [":authority", "www.example.com"],
          ["cache-control", "no-cache"]]
      doAssert hdecodeAll(ic, dh, d) == ic.len
      var i = 0
      for h in d:
        doAssert(d.s[h.n] == expected[i][0])
        doAssert(d.s[h.v] == expected[i][1])
        inc i
      doAssert i == expected.len
      doAssert dh.len == 2
      doAssert($dh ==
        "cache-control: no-cache\r\L" &
        ":authority: www.example.com\r\L")
    block:
      echo "Test Third Request"
      var ic = @[
        0x8287'u16, 0x85bf, 0x400a, 0x6375,
        0x7374, 0x6f6d, 0x2d6b, 0x6579,
        0x0c63, 0x7573, 0x746f, 0x6d2d,
        0x7661, 0x6c75].toBytes
      ic.add(byte 0x65'u16)
      var
        d = initDecodedStr()
        expected = [
          [":method", "GET"],
          [":scheme", "https"],
          [":path", "/index.html"],
          [":authority", "www.example.com"],
          ["custom-key", "custom-value"]]
      doAssert hdecodeAll(ic, dh, d) == ic.len
      var i = 0
      for h in d:
        doAssert(d.s[h.n] == expected[i][0])
        doAssert(d.s[h.v] == expected[i][1])
        inc i
      doAssert i == expected.len
      doAssert dh.len == 3
      doAssert($dh ==
        "custom-key: custom-value\r\L" &
        "cache-control: no-cache\r\L" &
        ":authority: www.example.com\r\L")

  block:
    echo "Test Request Examples with Huffman Coding"
    var dh = initDynHeaders(256)
    block:
      echo "Test First Request"
      var ic = @[
        0x8286'u16, 0x8441, 0x8cf1, 0xe3c2,
        0xe5f2, 0x3a6b, 0xa0ab, 0x90f4].toBytes
      ic.add(byte 0xff'u16)
      var
        d = initDecodedStr()
        expected = [
          [":method", "GET"],
          [":scheme", "http"],
          [":path", "/"],
          [":authority", "www.example.com"]]
      doAssert hdecodeAll(ic, dh, d) == ic.len
      var i = 0
      for h in d:
        doAssert(d.s[h.n] == expected[i][0])
        doAssert(d.s[h.v] == expected[i][1])
        inc i
      doAssert i == expected.len
      doAssert dh.len == 1
      doAssert $dh == ":authority: www.example.com\r\L"
    block:
      echo "Test Second Request"
      var
        ic = @[
          0x8286'u16, 0x84be, 0x5886,
          0xa8eb, 0x1064, 0x9cbf].toBytes
        d = initDecodedStr()
        expected = [
          [":method", "GET"],
          [":scheme", "http"],
          [":path", "/"],
          [":authority", "www.example.com"],
          ["cache-control", "no-cache"]]
      doAssert hdecodeAll(ic, dh, d) == ic.len
      var i = 0
      for h in d:
        doAssert(d.s[h.n] == expected[i][0])
        doAssert(d.s[h.v] == expected[i][1])
        inc i
      doAssert i == expected.len
      doAssert dh.len == 2
      doAssert($dh ==
        "cache-control: no-cache\r\L" &
        ":authority: www.example.com\r\L")
    block:
      echo "Test Third Request"
      var
        ic = @[
          0x8287'u16, 0x85bf, 0x4088, 0x25a8,
          0x49e9, 0x5ba9, 0x7d7f, 0x8925,
          0xa849, 0xe95b, 0xb8e8, 0xb4bf].toBytes
        d = initDecodedStr()
        expected = [
          [":method", "GET"],
          [":scheme", "https"],
          [":path", "/index.html"],
          [":authority", "www.example.com"],
          ["custom-key", "custom-value"]]
      doAssert hdecodeAll(ic, dh, d) == ic.len
      var i = 0
      for h in d:
        doAssert(d.s[h.n] == expected[i][0])
        doAssert(d.s[h.v] == expected[i][1])
        inc i
      doAssert i == expected.len
      doAssert dh.len == 3
      doAssert($dh ==
        "custom-key: custom-value\r\L" &
        "cache-control: no-cache\r\L" &
        ":authority: www.example.com\r\L")

    block:
      echo "Test Response Examples without Huffman Coding"
      var dh = initDynHeaders(256)
      block:
        echo "Test First Response"
        var
          ic = @[
            0x4803'u16, 0x3330, 0x3258, 0x0770,
            0x7269, 0x7661, 0x7465, 0x611d,
            0x4d6f, 0x6e2c, 0x2032, 0x3120,
            0x4f63, 0x7420, 0x3230, 0x3133,
            0x2032, 0x303a, 0x3133, 0x3a32,
            0x3120, 0x474d, 0x546e, 0x1768,
            0x7474, 0x7073, 0x3a2f, 0x2f77,
            0x7777, 0x2e65, 0x7861, 0x6d70,
            0x6c65, 0x2e63, 0x6f6d].toBytes
          d = initDecodedStr()
          expected = [
            [":status", "302"],
            ["cache-control", "private"],
            ["date", "Mon, 21 Oct 2013 20:13:21 GMT"],
            ["location", "https://www.example.com"]]
        doAssert hdecodeAll(ic, dh, d) == ic.len
        var i = 0
        for h in d:
          doAssert(d.s[h.n] == expected[i][0])
          doAssert(d.s[h.v] == expected[i][1])
          inc i
        doAssert i == expected.len
        doAssert dh.len == 4
        doAssert($dh ==
          "location: https://www.example.com\r\L" &
          "date: Mon, 21 Oct 2013 20:13:21 GMT\r\L" &
          "cache-control: private\r\L" &
          ":status: 302\r\L")
      block:
        echo "Test Second Response"
        var
          ic = @[
            0x4803'u16, 0x3330, 0x37c1, 0xc0bf].toBytes
          d = initDecodedStr()
          expected = [
            [":status", "307"],
            ["cache-control", "private"],
            ["date", "Mon, 21 Oct 2013 20:13:21 GMT"],
            ["location", "https://www.example.com"]]
        doAssert hdecodeAll(ic, dh, d) == ic.len
        var i = 0
        for h in d:
          doAssert(d.s[h.n] == expected[i][0])
          doAssert(d.s[h.v] == expected[i][1])
          inc i
        doAssert i == expected.len
        doAssert dh.len == 4
        doAssert($dh ==
          ":status: 307\r\L" &
          "location: https://www.example.com\r\L" &
          "date: Mon, 21 Oct 2013 20:13:21 GMT\r\L" &
          "cache-control: private\r\L")
      block:
        echo "Test Third Response"
        var
          ic = @[
            0x88c1'u16, 0x611d, 0x4d6f, 0x6e2c,
            0x2032, 0x3120, 0x4f63, 0x7420,
            0x3230, 0x3133, 0x2032, 0x303a,
            0x3133, 0x3a32, 0x3220, 0x474d,
            0x54c0, 0x5a04, 0x677a, 0x6970,
            0x7738, 0x666f, 0x6f3d, 0x4153,
            0x444a, 0x4b48, 0x514b, 0x425a,
            0x584f, 0x5157, 0x454f, 0x5049,
            0x5541, 0x5851, 0x5745, 0x4f49,
            0x553b, 0x206d, 0x6178, 0x2d61,
            0x6765, 0x3d33, 0x3630, 0x303b,
            0x2076, 0x6572, 0x7369, 0x6f6e,
            0x3d31].toBytes
          d = initDecodedStr()
          expected = [
            [":status", "200"],
            ["cache-control", "private"],
            ["date", "Mon, 21 Oct 2013 20:13:22 GMT"],
            ["location", "https://www.example.com"],
            ["content-encoding", "gzip"],
            ["set-cookie",
             "foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; max-age=3600; version=1"]]
        doAssert hdecodeAll(ic, dh, d) == ic.len
        var i = 0
        for h in d:
          doAssert(d.s[h.n] == expected[i][0])
          doAssert(d.s[h.v] == expected[i][1])
          inc i
        doAssert i == expected.len
        doAssert dh.len == 3
        doAssert($dh ==
          "set-cookie: foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; " &
          "max-age=3600; version=1\r\L" &
          "content-encoding: gzip\r\L" &
          "date: Mon, 21 Oct 2013 20:13:22 GMT\r\L")

    block:
      echo "Test Response Examples with Huffman Coding"
      var dh = initDynHeaders(256)
      block:
        echo "Test First Response"
        var
          ic = @[
            0x4882'u16, 0x6402, 0x5885, 0xaec3,
            0x771a, 0x4b61, 0x96d0, 0x7abe,
            0x9410, 0x54d4, 0x44a8, 0x2005,
            0x9504, 0x0b81, 0x66e0, 0x82a6,
            0x2d1b, 0xff6e, 0x919d, 0x29ad,
            0x1718, 0x63c7, 0x8f0b, 0x97c8,
            0xe9ae, 0x82ae, 0x43d3].toBytes
          d = initDecodedStr()
          expected = [
            [":status", "302"],
            ["cache-control", "private"],
            ["date", "Mon, 21 Oct 2013 20:13:21 GMT"],
            ["location", "https://www.example.com"]]
        doAssert hdecodeAll(ic, dh, d) == ic.len
        var i = 0
        for h in d:
          doAssert(d.s[h.n] == expected[i][0])
          doAssert(d.s[h.v] == expected[i][1])
          inc i
        doAssert i == expected.len
        doAssert dh.len == 4
        doAssert($dh ==
          "location: https://www.example.com\r\L" &
          "date: Mon, 21 Oct 2013 20:13:21 GMT\r\L" &
          "cache-control: private\r\L" &
          ":status: 302\r\L")
      block:
        echo "Test Second Response"
        var
          ic = @[
            0x4883'u16, 0x640e, 0xffc1, 0xc0bf].toBytes
          d = initDecodedStr()
          expected = [
            [":status", "307"],
            ["cache-control", "private"],
            ["date", "Mon, 21 Oct 2013 20:13:21 GMT"],
            ["location", "https://www.example.com"]]
        doAssert hdecodeAll(ic, dh, d) == ic.len
        var i = 0
        for h in d:
          doAssert(d.s[h.n] == expected[i][0])
          doAssert(d.s[h.v] == expected[i][1])
          inc i
        doAssert i == expected.len
        doAssert dh.len == 4
        doAssert($dh ==
          ":status: 307\r\L" &
          "location: https://www.example.com\r\L" &
          "date: Mon, 21 Oct 2013 20:13:21 GMT\r\L" &
          "cache-control: private\r\L")
      block:
        echo "Test Third Response"
        var ic = @[
          0x88c1'u16, 0x6196, 0xd07a, 0xbe94,
          0x1054, 0xd444, 0xa820, 0x0595,
          0x040b, 0x8166, 0xe084, 0xa62d,
          0x1bff, 0xc05a, 0x839b, 0xd9ab,
          0x77ad, 0x94e7, 0x821d, 0xd7f2,
          0xe6c7, 0xb335, 0xdfdf, 0xcd5b,
          0x3960, 0xd5af, 0x2708, 0x7f36,
          0x72c1, 0xab27, 0x0fb5, 0x291f,
          0x9587, 0x3160, 0x65c0, 0x03ed,
          0x4ee5, 0xb106, 0x3d50].toBytes
        ic.add(byte 0x07'u8)
        var
          d = initDecodedStr()
          expected = [
            [":status", "200"],
            ["cache-control", "private"],
            ["date", "Mon, 21 Oct 2013 20:13:22 GMT"],
            ["location", "https://www.example.com"],
            ["content-encoding", "gzip"],
            ["set-cookie",
             "foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; max-age=3600; version=1"]]
        doAssert hdecodeAll(ic, dh, d) == ic.len
        var i = 0
        for h in d:
          doAssert(d.s[h.n] == expected[i][0])
          doAssert(d.s[h.v] == expected[i][1])
          inc i
        doAssert i == expected.len
        doAssert dh.len == 3
        doAssert($dh ==
          "set-cookie: foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; " &
          "max-age=3600; version=1\r\L" &
          "content-encoding: gzip\r\L" &
          "date: Mon, 21 Oct 2013 20:13:22 GMT\r\L")
