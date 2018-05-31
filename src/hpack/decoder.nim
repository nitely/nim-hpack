## HPACK decoder

import
  huffman_decoder,
  headers_data,
  hcollections,
  exceptions

export
  hcollections,
  exceptions

type
  DecodeError* = object of HpackError

template raiseDecodeError(msg: string) =
  raise newException(DecodeError, msg)

proc intdecode(s: openArray[byte], n: int, d: var int): int =
  ## Return number of consumed octets.
  ## ``n`` param is the N-bit prefix.
  ## Decoded int is assigned to ``d``
  assert n in {1 .. 8}
  assert len(s) > 0
  result = 1
  d = 1 shl n - 1
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

type
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

proc clear*(d: var DecodedStr) {.inline.} =
  d.s.setLen(0)
  d.b.setLen(0)

proc reset*(d: var DecodedStr) {.deprecated.} =
  ## Deprecated, use ``clear()`` instead
  d.clear()

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

proc `$`*(d: DecodedStr): string {.inline.} =
  ## Use it for debugging purposes only
  result = ""
  for h in d:
    result.add(d.s[h.n])
    result.add(": ")
    result.add(d.s[h.v])
    result.add("\r\L")

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
    if hcdecode(s[n .. result-1], d.s) == -1:
      raiseDecodeError("huffman error")
    d.b.add(d.s.len)
  else:
    # todo: memcopy
    let j = d.s.len
    d.s.setLen(d.s.len + result-n)
    for i in 0 ..< result-n:
      d.s[j+i] = s[n+i].char
    d.b.add(d.s.len)

proc addIn(dh: DynHeaders, d: var DecodedStr, i: int) {.inline.} =
  let hb = dh[i]
  dh.substr(d.s, hb)
  d.b.add(d.s.len-hb.v.len)
  d.b.add(d.s.len)

proc addNameIn(dh: DynHeaders, d: var DecodedStr, i: int) {.inline.} =
  let hb = dh[i]
  dh.substr(d.s, initHBounds(hb.n, hb.n))
  d.b.add(d.s.len)

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
    let nh = strdecode(s[result .. s.len-1], d)
    if result > int.high-nh:
      raiseDecodeError("overflow")
    inc(result, nh)
  if result > s.len-1:
    raiseDecodeError("out of bounds")
  let nv = strdecode(s[result .. s.len-1], d)
  if result > int.high-nv:
    raiseDecodeError("overflow")
  inc(result, nv)
  when store:
    let hsl = d[^1]
    # todo: fixme: https://github.com/nim-lang/Nim/issues/7904
    if hsl.n.b >= hsl.n.a and hsl.v.b >= hsl.v.a:
      h.add(
        toOpenArray(d.s, hsl.n.a, hsl.n.b),
        toOpenArray(d.s, hsl.v.a, hsl.v.b))
    else:
      h.add(
        d.s[hsl.n.a .. hsl.n.b],
        d.s[hsl.v.a .. hsl.v.b])

proc hdecode*(
    s: openArray[byte],
    h: var DynHeaders,
    d: var DecodedStr,
    dhSize: var int): int
    {.raises: [DynHeadersError, DecodeError].} =
  ## Decode a single header.
  ## Return number of consumed octets.
  ## ``s`` bytes sequence must not be empty.
  ## ``dhSize`` will contain the
  ## dynamic table size update or
  ## ``-1`` otherwise
  assert len(s) > 0
  dhSize = -1
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
    result = litdecode(s, h, d, 6, true)
    return
  # without indexing or
  # never indexed
  if s[0] shr 4 <= 1:
    result = litdecode(s, h, d, 4, false)
    return
  # dyn table size update
  if s[0] shr 5 == 1:
    result = intdecode(s, 5, dhSize)
    return
  raiseDecodeError("unknown octet prefix")

# todo: remove
proc hdecode*(
    s: openArray[byte],
    h: var DynHeaders,
    d: var DecodedStr): int
    {.raises: [DynHeadersError, DecodeError].} =
  var dhSize = 0
  result = hdecode(s, h, d, dhSize)

proc hdecodeAll*(
    s: openArray[byte],
    h: var DynHeaders,
    d: var DecodedStr,
    dhSize: var int)
    {.raises: [DynHeadersError, DecodeError].} =
  ## Decode all headers from the blob of bytes
  ## ``s`` and stores it into a decoded string``d``.
  ## The dynamic headers are stored into ``h``
  ## to decode the next message.
  ## The dynamic table size update is stored
  ## into ``dhSize``, default to ``-1``
  ## if there's no update
  var i = 0
  while i < s.len:
    inc(i, hdecode(toOpenArray(s, i, s.len-1), h, d, dhSize))
  assert i == s.len

# todo: remove
proc hdecodeAll*(
    s: openArray[byte],
    h: var DynHeaders,
    d: var DecodedStr)
    {.raises: [DynHeadersError, DecodeError].} =
  var dhSize = 0
  hdecodeAll(s, h, d, dhSize)

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
    var ds = initDecodedStr()
    ds.add("foo")
    ds.add("")
    doAssert ds.s[ds[^1].n] == "foo"
    doAssert ds.s[ds[^1].v] == ""

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
