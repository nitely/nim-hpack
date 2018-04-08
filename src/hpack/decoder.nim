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
    d = s[0].int
    return
  var
    cb = 1 shl 7
    shd = int.high
    b, m = 0
  # MSB == 1 means the value
  # continues in next byte
  while result < len(s) and (cb and (1 shl 7)) > 0:
    cb = s[result].int
    b = cb and 0x7f
    if b > shd:
      result = -1
      return
    b = b shl m
    if d > int.high - b:
      result = -1
      return
    inc(d, b)
    inc(m, 7)
    shd = shd shr 7
    inc result
  if (cb and (1 shl 7)) > 0:
    result = -1

when isMainModule:
  block:
    echo "Test Encoding 10 Using a 5-Bit Prefix"
    var
      ic = @[byte 0b01010]
      d = 0
    doAssert(intdecode(ic, 5, d) == 1)
    doAssert(d == 10)
  block:
    echo "Encoding 1337 Using a 5-Bit Prefix"
    var
      ic = @[byte 0b00011111, 0b10011010, 0b00001010]
      d = 0
    doAssert(intdecode(ic, 5, d) == 3)
    doAssert(d == 1337)
  block:
    echo "Encoding 42 Starting at an Octet Boundary"
    var
      ic = @[byte 0b00101010]
      d = 0
    doAssert(intdecode(ic, 8, d) == 1)
    doAssert(d == 42)
  block:
    echo "Bad lit int"
    var
      ic = @[byte 0b00011111, 0b10011010]
      d = 0
    doAssert(intdecode(ic, 5, d) == -1)
  block:
    echo "Long lit int32"
    var
      ic = @[
        byte 0b11111111, 0b11111111,
        0b11111111, 0b01111111]
      d = 0
    doAssert(intdecode(ic, 8, d) == 4)
    doAssert(d == 2097406)
  block:
    echo "Bad long lit int"
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
    echo "Bad long long lit int"
    var ic = @[byte 0b11111111]
    for _ in 0 ..< 123:  # add zeroes
      ic.add(0b10000000)
    ic.add(0b01111111)
    var d = 0
    doAssert(intdecode(ic, 8, d) == -1)
  block:
    echo "Long long lit int"
    var ic = @[byte 0b11111111]
    for _ in 0 ..< 123:  # add zeroes
      ic.add(0b10000000)
    ic.add(0b0)
    var d = 0
    doAssert(intdecode(ic, 8, d) == 125)
    doAssert(d == 255)
