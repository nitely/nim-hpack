## HPACK decoder

{.push raises: [].}

import
  ./huffman_decoder,
  ./headers_data,
  ./hcollections,
  ./exceptions,
  ./utils

export
  exceptions,
  HpackBound,
  initHpackBound,
  Hpack,
  initHpack

type
  NbitPref = range[1 .. 8]
  DecodeError* = object of HpackError

template raiseDecodeError(msg: string) =
  raise newException(DecodeError, msg)

proc intdecode(
  s: openArray[byte],
  n: NbitPref,
  d: var int
): int {.inline, raises: [DecodeError].} =
  ## Return number of consumed octets.
  ## ``n`` param is the N-bit prefix.
  ## Decoded int is assigned to ``d``
  assert len(s) > 0
  result = 1
  d = (1 shl n) - 1
  if (s[0].int and d) < d:
    d = s[0].int and d
    return
  var
    cb = 1 shl 7  # continue
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

proc strdecode(
  s: openArray[byte],
  ss: var seq[byte]
): int {.inline, raises: [DecodeError].} =
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
    if hcdecode(toOpenArray(s, n, result-1), ss) == -1:
      raiseDecodeError("huffman error")
  else:
    let L = ss.len
    ss.setLenUninit2(L + result-n)
    strcopy(ss, s, L, n, result-n)

proc hname(
  dh: Hpack,
  i: int,
  ss: var seq[byte],
  nn: var Slice[int]
) {.inline, raises: [DecodeError].} =
  ## Add header's name of static/dynamic table
  ## in ``i`` position into a decoded string
  assert i > 0
  let L = ss.len
  let i = i-1
  let idyn = i-headersTable.len
  if i < len(headersTable):
    ss.add headersTable[i][0].asBytes
  elif idyn < dh.len:
    substr(dh, ss, dh[idyn].n)
  else:
    raiseDecodeError("dyn header name not found")
  nn = L .. ss.len-1
  ss.add ':'.byte
  ss.add ' '.byte

proc header(
  dh: Hpack,
  i: int,
  ss: var seq[byte],
  nn, vv: var Slice[int]
) {.inline, raises: [DecodeError].} =
  ## Add header of static/dynamic table
  ## in ``i`` position into a decoded string
  assert i > 0
  let i = i-1
  let idyn = i-headersTable.len
  if i < headersTable.len:
    nn.a = ss.len
    ss.add headersTable[i][0].asBytes
    nn.b = ss.len-1
    ss.add ':'.byte
    ss.add ' '.byte
    vv.a = ss.len
    ss.add headersTable[i][1].asBytes
    vv.b = ss.len-1
    ss.add '\r'.byte
    ss.add '\n'.byte
  elif idyn < dh.len:
    nn.a = ss.len
    dh.substr(ss, dh[idyn].n)
    nn.b = ss.len-1
    ss.add ':'.byte
    ss.add ' '.byte
    vv.a = ss.len
    dh.substr(ss, dh[idyn].v)
    vv.b = ss.len-1
    ss.add '\r'.byte
    ss.add '\n'.byte
  else:
    raiseDecodeError("dyn header not found")

proc litdecode(
  s: openArray[byte],
  dh: var Hpack,
  ss: var seq[byte],
  nn, vv: var Slice[int],
  np: NbitPref,
  store: bool
): int {.inline, raises: [DecodeError].} =
  ## Decode literal header field:
  ## with incremental indexing,
  ## without indexing, or
  ## never indexed.
  ## Return number of consumed octets
  var dint = 0
  result = intdecode(s, np, dint)
  if dint > 0:
    hname(dh, dint, ss, nn)
  else:
    if result > s.len-1:
      raiseDecodeError("out of bounds")
    let L = ss.len
    let nh = strdecode(toOpenArray(s, result, s.len-1), ss)
    nn = L .. ss.len-1
    ss.add ':'.byte
    ss.add ' '.byte
    if result > int.high-nh:
      raiseDecodeError("overflow")
    inc(result, nh)
  if result > s.len-1:
    raiseDecodeError("out of bounds")
  let L = ss.len
  let nv = strdecode(toOpenArray(s, result, s.len-1), ss)
  vv = L .. ss.len-1
  ss.add '\r'.byte
  ss.add '\n'.byte
  if result > int.high-nv:
    raiseDecodeError("overflow")
  inc(result, nv)
  if store:
    dh.add(
      toOpenArray(ss, nn.a, nn.b),
      toOpenArray(ss, vv.a, vv.b)
    )

proc hdecode*(
  s: openArray[byte],
  dh: var Hpack,
  ss: var seq[byte],
  nn, vv: var Slice[int],
  dhSize: var int
): int {.raises: [DecodeError].} =
  ## Decode a single header.
  ## Return number of consumed octets.
  ## ``s`` bytes sequence must not be empty.
  ## ``dhSize`` will contain the
  ## dynamic table size update or
  ## ``-1`` otherwise
  assert len(s) > 0
  dhSize = -1
  nn = 0 .. -1
  vv = 0 .. -1
  # indexed
  if s[0] shr 7 == 1:
    var dint = 0
    result = intdecode(s, 7, dint)
    if dint == 0:
      raiseDecodeError("invalid header index 0")
    header(dh, dint, ss, nn, vv)
    return
  # incremental indexing
  if s[0] shr 6 == 1:
    result = litdecode(s, dh, ss, nn, vv, 6, true)
    return
  # without indexing or
  # never indexed
  if s[0] shr 4 <= 1:
    result = litdecode(s, dh, ss, nn, vv, 4, false)
    return
  # dyn table size update
  # https://www.rfc-editor.org/rfc/rfc7541.html#section-6.3
  if s[0] shr 5 == 1:
    result = intdecode(s, 5, dhSize)
    if dhSize > dh.maxSize:
      raiseDecodeError("dyn table size update exceeds the max size")
    return
  raiseDecodeError("unknown octet prefix")

proc hdecode*(
  s: openArray[byte],
  dh: var Hpack,
  ss: var string,
  nn, vv: var Slice[int],
  dhSize: var int
): int {.raises: [DecodeError].} =
  ## Compat; slower than the ``seq[byte]`` version
  let L = ss.len
  var b = newSeq[byte]()
  defer: ss.add b.toString
  result = hdecode(s, dh, b, nn, vv, dhSize)
  if dhSize == -1:
    nn = nn.a+L .. nn.b+L
    vv = vv.a+L .. vv.b+L

func setSize*(dh: var Hpack, dhSize: int) =
  hcollections.setSize(dh, dhSize)

proc hdecodeAll*(
  s: openArray[byte],
  dh: var Hpack,
  ss: var seq[byte],
  bb: var seq[HpackBound]
) {.raises: [DecodeError].} =
  ## Decode all headers from the blob of bytes
  ## ``s`` and stores it into a decoded string``d``.
  ## The dynamic headers are stored into ``h``
  ## to decode the next message.
  var dhSize = -1
  var nn = 0 .. -1
  var vv = 0 .. -1
  var i = 0
  while i < s.len:
    i += hdecode(
      toOpenArray(s, i, s.len-1),
      dh, ss, nn, vv, dhSize
    )
    if dhSize > -1:
      hcollections.setSize(dh, dhSize)
    else:
      bb.add initHpackBound(nn, vv)
  assert i == s.len

proc hdecodeAll*(
  s: openArray[byte],
  dh: var Hpack,
  ss: var string,
  bb: var seq[HpackBound]
) {.raises: [DecodeError].} =
  ## Compat; slower than the ``seq[byte]`` version
  var b = @(ss.asBytes)
  defer: ss = b.toString
  hdecodeAll(s, dh, b, bb)

when isMainModule:
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
      s = newSeq[byte]()
    doAssert(strdecode(ic, s) == ic.len)
    doAssert(s.toString == "custom-key")
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
      s = newSeq[byte]()
    doAssert(strdecode(ic, s) == ic.len)
    doAssert(s.toString == "custom-header")
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
      s = newSeq[byte]()
    doAssert(strdecode(ic, s) == ic.len)
    doAssert(s.toString == "/sample/path")
  block:
    var
      ic = @[
        byte 0b00001000, 0b01110000,
        0b01100001, 0b01110011,
        0b01110011, 0b01110111,
        0b01101111, 0b01110010,
        0b01100100]
      s = newSeq[byte]()
    doAssert(strdecode(ic, s) == ic.len)
    doAssert(s.toString == "password")
  block:
    var
      ic = @[
        byte 0b00000110, 0b01110011,
        0b01100101, 0b01100011,
        0b01110010, 0b01100101,
        0b01110100]
      s = newSeq[byte]()
    doAssert(strdecode(ic, s) == ic.len)
    doAssert(s.toString == "secret")
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
      s = newSeq[byte]()
    doAssert(strdecode(ic, s) == ic.len)
    doAssert(s.toString == "www.example.com")
  block:
    var
      ic = @[
        byte 0b00001000, 0b01101110,
        0b01101111, 0b00101101,
        0b01100011, 0b01100001,
        0b01100011, 0b01101000,
        0b01100101]
      s = newSeq[byte]()
    doAssert(strdecode(ic, s) == ic.len)
    doAssert(s.toString == "no-cache")
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
      s = newSeq[byte]()
    doAssert(strdecode(ic, s) == ic.len)
    doAssert(s.toString == "www.example.com")
