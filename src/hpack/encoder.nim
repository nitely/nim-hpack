## HPACK encoder

import huffman_encoder

proc intencode(x: int, n: int, s: var seq[byte]): int =
  ## Encode using N-bit prefix.
  ## Return number of octets.
  ## First byte's bit 2^N is set for convenience
  assert n in {1 .. 8}
  result = 1
  let np = 1 shl n - 1
  if x < np:
    s.add(x.uint8 or (1'u8 shl n))
    return
  s.add(np.uint8 or (1'u8 shl n))
  var x = x - np
  var i = 0
  while x >= 1 shl 7:
    s.add((x and (1 shl 7 - 1)).uint8 or 1'u8 shl 7)
    x = x shr 7
    inc result
  s.add(x.uint8)
  inc result

when isMainModule:
  import decoder

  block:
    echo "Test Encoding 10 Using a 5-Bit Prefix"
    var ic = newSeq[byte]()
    doAssert(intencode(10, 5, ic) == 1)
    doAssert(ic == @[byte 0b101010])
  block:
    echo "Test Encoding 1337 Using a 5-Bit Prefix"
    var ic = newSeq[byte]()
    doAssert(intencode(1337, 5, ic) == 3)
    doAssert(ic == @[byte 0b00111111, 0b10011010, 0b00001010])
  block:
    echo "Test Encoding 42 Starting at an Octet Boundary"
    var ic = newSeq[byte]()
    doAssert(intencode(42, 8, ic) == 1)
    doAssert(ic == @[byte 0b00101010])
  block:
    echo "Test Long lit int32"
    var ic = newSeq[byte]()
    doAssert(intencode(2097406, 8, ic) == 4)
    doAssert(ic == @[
      byte 0b11111111, 0b11111111,
      0b11111111, 0b01111111])
