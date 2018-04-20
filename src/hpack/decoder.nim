## WIP, highly un-optimized decoder

import deques

import huffman_decoder
import headers_data

proc intdecode*(s: openArray[byte], n: int, d: var int): int =
  ## Return number of consumed octets.
  ## Return ``-1`` on error.
  ## ``n`` param is the N-bit prefix.
  ## Decoded int is assigned to ``d``.
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
      result = -1
      return
    b = b shl m
    if d > int.high - b:
      result = -1
      return
    inc(d, b)
    inc(m, 7)
    sf = sf shr 7
    inc result
  if cb shr 7 == 1:
    result = -1

proc strdecode(s: openArray[byte], d: var string): int =
  ## Decode a literal string.
  ## Return number of consumed octets.
  ## Return ``-1`` on error.
  ## Decoded string is appended to ``d``.
  assert len(s) > 0
  var dint = 0
  let n = intdecode(s, 7, dint)
  if n == -1:
    result = -1
    return
  if dint > int.high-n:
    result = -1
    return
  result = n+dint
  if result > len(s):
    result = -1
    return
  if s[0] shr 7 == 1:  # huffman encoded
    if hcdecode(toOpenArray(s, n, result-1), d) == -1:
      result = -1
      return
  else:
    let j = len(d)
    d.setLen(len(d) + result-n)
    for i in 0 ..< result-n:
      d[j+i] = s[n+i].char

type
  Header = object
    h: string
    spl: int
  Headers = Deque[Header]
  ## Headers dynamic list

proc hname(h: Headers, d: var string, i: int): int =
  assert i > 0
  result = 0
  var i = i-1
  if i < len(headersTable):
    echo headersTable[i][0]
    d.add(headersTable[i][0])
  elif i < i-len(headersTable):
    let hr = h[i-len(headersTable)]
    echo hr.h[0 ..< hr.spl]
    d.add(hr.h[0 ..< hr.spl])
  else:
    result = -1

proc header(h: Headers, d: var string, i: int): int =
  assert i > 0
  result = 0
  var i = i-1
  if i < len(headersTable):
    echo headersTable[i]
    d.add(headersTable[i][0])
    d.add(headersTable[i][1])
  elif i < i-len(headersTable):
    echo h[i-len(headersTable)]
    d.add(h[i-len(headersTable)].h)
  else:
    result = -1

proc litdecode(
    s: seq[byte],
    h: var Headers,
    d: var string,
    np: int,
    store: static[bool]): int =
  ## Decode literal header field:
  ## with incremental indexing,
  ## without indexing, or
  ## never indexed.
  ## Return number of consmed
  ## octets, or -1 on error
  result = 0
  var dint = 0
  let n = intdecode(s, np, dint)
  if n == -1:
    result = -1
    return
  inc(result, n)
  if dint > 0:
    if hname(h, d, dint) == -1:
      result = -1
      return
  else:
    # todo: check 1 < len(s)
    let nh = strdecode(toOpenArray(s, result, len(s)-1), d)
    if nh == -1:
      result = -1
      return
    inc(result, nh)
  # todo: check 1+nh < len(s) and does not overflow
  let nv = strdecode(toOpenArray(s, result, len(s)-1), d)
  if nv == -1:
    result = -1
    return
  inc(result, nv)
  when store:
    # todo: fixme
    h.addFirst(Header(
      h: "hnamehvalue",
      spl: 5))

proc hdecode(s: seq[byte], h: var Headers, d: var string): int =
  ## Decode a header.
  ## Return number of consmed
  ## octets, or -1 on error
  assert len(s) > 0
  # indexed
  if s[0] shr 7 == 1:
    var dint = 0
    result = intdecode(s, 7, dint)
    if result == -1:
      return
    if dint == 0:
      result = -1
      return
    if header(h, d, dint) == -1:
      result = -1
      return
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
    doAssert(intdecode(ic, 5, d) == -1)
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
    doAssert(intdecode(ic, 8, d) == -1)
  block:
    echo "Test Bad lit int with too many zeros in the middle"
    var ic = @[byte 0b11111111]
    for _ in 0 ..< 123:  # add zeroes
      ic.add(0b10000000)
    ic.add(0b01111111)
    var d = 0
    doAssert(intdecode(ic, 8, d) == -1)
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
      d = ""
    doAssert(strdecode(ic, d) == ic.len)
    doAssert(d == "custom-key")
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
      d = ""
    doAssert(strdecode(ic, d) == ic.len)
    doAssert(d == "custom-header")
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
      d = ""
    doAssert(strdecode(ic, d) == ic.len)
    doAssert(d == "/sample/path")
  block:
    var
      ic = @[
        byte 0b00001000, 0b01110000,
        0b01100001, 0b01110011,
        0b01110011, 0b01110111,
        0b01101111, 0b01110010,
        0b01100100]
      d = ""
    doAssert(strdecode(ic, d) == ic.len)
    doAssert(d == "password")
  block:
    var
      ic = @[
        byte 0b00000110, 0b01110011,
        0b01100101, 0b01100011,
        0b01110010, 0b01100101,
        0b01110100]
      d = ""
    doAssert(strdecode(ic, d) == ic.len)
    doAssert(d == "secret")
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
      d = ""
    doAssert(strdecode(ic, d) == ic.len)
    doAssert(d == "www.example.com")
  block:
    var
      ic = @[
        byte 0b00001000, 0b01101110,
        0b01101111, 0b00101101,
        0b01100011, 0b01100001,
        0b01100011, 0b01101000,
        0b01100101]
      d = ""
    doAssert(strdecode(ic, d) == ic.len)
    doAssert(d == "no-cache")
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
      d = ""
    doAssert(strdecode(ic, d) == ic.len)
    doAssert(d == "www.example.com")

  proc toBytes(s: seq[uint16]): seq[byte] =
    result = newSeqOfCap[byte](len(s) * 2)
    for b in s:
      result.add(byte(b shr 8))
      result.add(byte(b and 0xff))

  block:
    echo "Test Literal Header Field with Indexing"
    var
      ic = @[
        0x400a'u16, 0x6375, 0x7374, 0x6f6d,
        0x2d6b, 0x6579, 0x0d63, 0x7573,
        0x746f, 0x6d2d, 0x6865, 0x6164, 0x6572].toBytes
      d = ""
      h = initDeque[Header](32)
    doAssert(hdecode(ic, h, d) == ic.len)
    doAssert(d == "custom-keycustom-header")
    echo d
    doAssert(h.len == 1)
    # todo: check header in h
