## WIP, highly un-optimized decoder

import deques
import math

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

proc intdecode*(bits: seq[byte], n: int8): uint32 =
  ## ``n`` param is the N-bit prefix
  assert n in {1 .. 8}
  if len(bits) == 0:
    return
  result = bits[0]
  if (bits[0] and 1'u8 shl (n - 1)) == 0'u8:
    return
  var
    b = 0x80'u8
    i = 1
    m = 0'u8
  # MSB == 1 means the value
  # continues in next byte
  while (b and 0x80'u8) > 0'u8 and i < len(bits):
    b = bits[i]
    result += (b and 0x7f'u8).uint32 shl m
    m += 7'u8
    inc i

when isMainModule:
  block:
    echo "Test Encoding 10 Using a 5-Bit Prefix"
    let ic = @[byte 0b01010]
    doAssert(intdecode(ic, 5) == 10)
  block:
    echo "Encoding 1337 Using a 5-Bit Prefix"
    let ic = @[
      byte 0b00011111, 0b10011010, 0b00001010]
    doAssert(intdecode(ic, 5) == 1337)
  block:
    echo "Encoding 42 Starting at an Octet Boundary"
    let ic = @[byte 0b00101010]
    doAssert(intdecode(ic, 8) == 42)
