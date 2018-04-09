## WIP, highly un-optimized decoder

import deques
import math

import huffman_decoder

# todo: use single string + seq[slice]
type
  DynEntry = object
    n: string
    v: string
  DynTable = object
    data: Deque[DynEntry]
    used: int
    maxSize: int

proc initDynTable(maxSize = 4): DynTable =
  DynTable(
    data: initDeque[DynEntry](16),
    used: 0,
    maxSize: maxSize)

proc push(t: var DynTable, e: DynEntry) =
  addFirst(t.data, e)
  inc(t.used, len(e.n))
  inc(t.used, len(e.v))

proc pop(t: var DynTable) =
  let e = popLast(t.data)
  dec(t.used, len(e.n))
  dec(t.used, len(e.v))

proc intdecode*(s: seq[byte], n: int, d: var int): int =
  ## Return number of consumed octets.
  ## Return ``-1`` on error.
  ## ``n`` param is the N-bit prefix.
  ## Decoded int is assigned to ``d`` param.
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
  while result < len(s) and (cb and (1 shl 7)) > 0:
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
  if (cb and (1 shl 7)) > 0:
    result = -1

proc strdecode(s: seq[byte]): string =
  assert len(s) > 0
  result = ""
  var d = 0
  let n = intdecode(s, 7, d)
  if d > int.high - n:
    return
  let m = n+d
  if n == -1 or m > len(s):
    return
  if (s[0].int and (1 shl 7)) > 0:  # huffman encoded
    let n = hcdecode(toOpenArray(s, n, m-1), result)
    if n == -1:
      result.setLen(0)
      return
  else:
    for b in s[n ..< m]:
      result.add(b.char)

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
    let ic = @[
      byte 0b00001010, 0b01100011,
      0b01110101, 0b01110011,
      0b01110100, 0b01101111,
      0b01101101, 0b00101101,
      0b01101011, 0b01100101,
      0b01111001]
    doAssert(strdecode(ic) == "custom-key")
  block:
    let ic = @[
      byte 0b00001101, 0b01100011,
      0b01110101, 0b01110011,
      0b01110100, 0b01101111,
      0b01101101, 0b00101101,
      0b01101000, 0b01100101,
      0b01100001, 0b01100100,
      0b01100101, 0b01110010]
    doAssert(strdecode(ic) == "custom-header")
  block:
    let ic = @[
      byte 0b00001100, 0b00101111,
      0b01110011, 0b01100001,
      0b01101101, 0b01110000,
      0b01101100, 0b01100101,
      0b00101111, 0b01110000,
      0b01100001, 0b01110100,
      0b01101000]
    doAssert(strdecode(ic) == "/sample/path")
  block:
    let ic = @[
      byte 0b00001000, 0b01110000,
      0b01100001, 0b01110011,
      0b01110011, 0b01110111,
      0b01101111, 0b01110010,
      0b01100100]
    doAssert(strdecode(ic) == "password")
  block:
    let ic = @[
      byte 0b00000110, 0b01110011,
      0b01100101, 0b01100011,
      0b01110010, 0b01100101,
      0b01110100]
    doAssert(strdecode(ic) == "secret")
  block:
    let ic = @[
      byte 0b00001111, 0b01110111,
      0b01110111, 0b01110111,
      0b00101110, 0b01100101,
      0b01111000, 0b01100001,
      0b01101101, 0b01110000,
      0b01101100, 0b01100101,
      0b00101110, 0b01100011,
      0b01101111, 0b01101101]
    doAssert(strdecode(ic) == "www.example.com")
  block:
    let ic = @[
      byte 0b00001000, 0b01101110,
      0b01101111, 0b00101101,
      0b01100011, 0b01100001,
      0b01100011, 0b01101000,
      0b01100101]
    doAssert(strdecode(ic) == "no-cache")
  block:
    echo "Test Request Examples with Huffman Coding"
    let ic = @[
      byte 0b10001100, 0b11110001,
      0b11100011, 0b11000010,
      0b11100101, 0b11110010,
      0b00111010, 0b01101011,
      0b10100000, 0b10101011,
      0b10010000, 0b11110100,
      0b11111111]
    doAssert(strdecode(ic) == "www.example.com")
