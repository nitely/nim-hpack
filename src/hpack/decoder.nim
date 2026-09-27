## HPACK decoder

import
  ./huffman_decoder,
  ./headers_data,
  ./hcollections,
  ./exceptions

export
  hcollections,
  exceptions

type
  NbitPref = range[1 .. 8]
  DecodeError* = object of HpackError

template raiseDecodeError(msg: string) =
  raise newException(DecodeError, msg)

proc intdecode(s: openArray[byte], n: NbitPref, d: var int): int {.inline.} =
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

type
  StrLit = object
    ## String literal payload bounds
    a, b: int
    huffman: bool

func parseStr(s: openArray[byte], i: int, x: var StrLit): int {.inline.} =
  ## Parse the string literal at ``s[i]``.
  ## Return number of consumed octets.
  if i >= s.len:
    raiseDecodeError("out of bounds")
  var n = 0
  let hl = intdecode(toOpenArray(s, i, s.len-1), 7, n)
  if n > s.len-i-hl:
    raiseDecodeError("out of bounds")
  x = StrLit(a: i+hl, b: i+hl+n, huffman: s[i] shr 7 == 1)
  result = hl+n

func maxLen(x: StrLit): int {.inline.} =
  if x.huffman: hcdecodeMaxLen(x.b-x.a) else: x.b-x.a

func writeStr(
  s: openArray[byte], x: StrLit, ss: var string, i: int
): int {.inline.} =
  ## Write the decoded string into ``ss[i]``.
  ## Return the decoded length, or -1 on error.
  ## ``ss`` must have room for ``x.maxLen``
  if x.huffman:
    result = hcdecode(toOpenArray(s, x.a, x.b-1), toOpenArray(ss, i, ss.len-1))
  else:
    result = x.b-x.a
    if result > 0:
      copyMem(addr ss[i], unsafeAddr s[x.a], result)

func tableNameLen(dh: DynHeaders, i: int): int {.inline.} =
  ## Length of the name of the static/dynamic
  ## table entry at index ``i``
  let idyn = i-headersTable.len
  if i < headersTable.len:
    headersTable[i][0].len
  elif idyn < dh.len:
    dh.nameLen(idyn)
  else:
    raiseDecodeError("dyn header name not found")

func writeName(dh: DynHeaders, i: int, ss: var string, j: int): int {.inline.} =
  ## Write the name of the table entry at index
  ## ``i`` into ``ss[j]``; return its length.
  ## The index must be valid
  if i < headersTable.len:
    result = headersTable[i][0].len
    copyMem(addr ss[j], unsafeAddr headersTable[i][0][0], result)
  else:
    result = dh.nameLen(i-headersTable.len)
    dh.copyName(i-headersTable.len, toOpenArray(ss, j, ss.len-1))

func buildStaticLines(): array[headersTable.len, string] =
  for i, h in pairs headersTable:
    result[i] = h[0] & ": " & h[1] & "\r\n"

const staticLines = buildStaticLines()

template writeSep(ss: var string, i: var int, a, b: char) =
  ss[i] = a
  ss[i+1] = b
  inc(i, 2)

proc header(
  dh: DynHeaders,
  i: int,
  ss: var string,
  nn, vv: var Slice[int]
) {.inline.} =
  ## Add header of static/dynamic table
  ## in ``i`` position into a decoded string.
  ## The index must be valid
  let L = ss.len
  var nLen, lineLen = 0
  if i < headersTable.len:
    nLen = headersTable[i][0].len
    lineLen = staticLines[i].len
    ss.setLen(L + lineLen)
    copyMem(addr ss[L], unsafeAddr staticLines[i][0], lineLen)
  else:
    let idyn = i-headersTable.len
    nLen = dh.nameLen(idyn)
    lineLen = dh.lineLen(idyn)
    ss.setLen(L + lineLen)
    dh.copyLine(idyn, toOpenArray(ss, L, ss.len-1))
  nn = L .. L+nLen-1
  vv = L+nLen+2 .. L+lineLen-3

proc litdecode(
  s: openArray[byte],
  dh: var DynHeaders,
  ss: var string,
  nn, vv: var Slice[int],
  np: NbitPref,
  store: bool
): int {.inline.} =
  ## Decode literal header field:
  ## with incremental indexing,
  ## without indexing, or
  ## never indexed.
  ## Return number of consumed octets
  var nameIdx = 0
  var nameLit, valueLit: StrLit
  result = intdecode(s, np, nameIdx)
  dec nameIdx  # to 0-based; -1 means literal name
  var nameMax = 0
  if nameIdx >= 0:
    nameMax = tableNameLen(dh, nameIdx)
  else:
    inc(result, parseStr(s, result, nameLit))
    nameMax = nameLit.maxLen
  inc(result, parseStr(s, result, valueLit))
  let L = ss.len
  ss.setLen(L + nameMax + valueLit.maxLen + 4)
  var j = L
  if nameIdx >= 0:
    inc(j, writeName(dh, nameIdx, ss, j))
  else:
    let n = writeStr(s, nameLit, ss, j)
    if n == -1:
      ss.setLen(L)
      raiseDecodeError("huffman error")
    inc(j, n)
  nn = L .. j-1
  writeSep(ss, j, ':', ' ')
  vv.a = j
  let n = writeStr(s, valueLit, ss, j)
  if n == -1:
    ss.setLen(L)
    raiseDecodeError("huffman error")
  inc(j, n)
  vv.b = j-1
  writeSep(ss, j, '\r', '\n')
  ss.setLen(j)
  if store:
    dh.addLine(toOpenArray(ss, L, j-1), nn.len)

proc hdecode*(
  s: openArray[byte],
  dh: var DynHeaders,
  ss: var string,
  nn, vv: var Slice[int],
  dhSize: var int
): Natural {.raises: [DecodeError].} =
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
    if dint-1 >= headersTable.len+dh.len:
      raiseDecodeError("dyn header not found")
    header(dh, dint-1, ss, nn, vv)
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

proc hdecodeAll*(
  s: openArray[byte],
  dh: var DynHeaders,
  ss: var string,
  bb: var seq[HBounds]
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
      dh.setSize dhSize
    else:
      bb.add initHBounds(nn, vv)
  assert i == s.len

when isMainModule:
  proc strdecode(s: openArray[byte], ss: var string): int =
    var x: StrLit
    result = parseStr(s, 0, x)
    let L = ss.len
    ss.setLen(L + x.maxLen)
    let n = writeStr(s, x, ss, L)
    doAssert n != -1
    ss.setLen(L + n)

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
      s = ""
    doAssert(strdecode(ic, s) == ic.len)
    doAssert(s == "custom-key")
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
      s = ""
    doAssert(strdecode(ic, s) == ic.len)
    doAssert(s == "custom-header")
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
      s = ""
    doAssert(strdecode(ic, s) == ic.len)
    doAssert(s == "/sample/path")
  block:
    var
      ic = @[
        byte 0b00001000, 0b01110000,
        0b01100001, 0b01110011,
        0b01110011, 0b01110111,
        0b01101111, 0b01110010,
        0b01100100]
      s = ""
    doAssert(strdecode(ic, s) == ic.len)
    doAssert(s == "password")
  block:
    var
      ic = @[
        byte 0b00000110, 0b01110011,
        0b01100101, 0b01100011,
        0b01110010, 0b01100101,
        0b01110100]
      s = ""
    doAssert(strdecode(ic, s) == ic.len)
    doAssert(s == "secret")
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
      s = ""
    doAssert(strdecode(ic, s) == ic.len)
    doAssert(s == "www.example.com")
  block:
    var
      ic = @[
        byte 0b00001000, 0b01101110,
        0b01101111, 0b00101101,
        0b01100011, 0b01100001,
        0b01100011, 0b01101000,
        0b01100101]
      s = ""
    doAssert(strdecode(ic, s) == ic.len)
    doAssert(s == "no-cache")
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
      s = ""
    doAssert(strdecode(ic, s) == ic.len)
    doAssert(s == "www.example.com")
