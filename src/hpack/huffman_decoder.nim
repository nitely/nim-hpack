import ./huffman_data

const lutBits = 12  # codes up to this length are decoded by a table lookup

type LutEntry = object
  sym, len: uint8  # len == 0 means the code is longer than lutBits

func buildLut(): array[1 shl lutBits, LutEntry] =
  for sym in 0 .. 255:
    let (code, L) = (hcDecTable[sym][0].int, hcDecTable[sym][1].int)
    if L > lutBits:
      continue
    # every index prefixed by the code
    let first = code shl (lutBits - L)
    for i in first ..< first + (1 shl (lutBits - L)):
      result[i] = LutEntry(sym: sym.uint8, len: L.uint8)

const lut = buildLut()

func decodeLong(bits: uint64, nbits: int, sym, L: var int): bool =
  ## Decode a code longer than lutBits prefixing
  ## the left aligned ``bits``. These are rare
  for i in 0 .. 255:
    let (code, L2) = (hcDecTable[i][0].uint64, hcDecTable[i][1].int)
    if L2 > lutBits and L2 <= nbits and code == bits shr (64 - L2):
      sym = i
      L = L2
      return true
  return false

proc hcdecode*(s: openArray[byte], d: var string): int =
  ## Huffman decoder.
  ## Return length of the decoded string.
  ## Return -1 on error.
  ## Decoded string is appended to param ``d``.
  ## If there's an error, ``d``
  ## may contain a partial decoded string
  var
    bits = 0'u64  # left aligned; bits past nbits are zero
    nbits = 0
    pos = 0
    sym, L = 0
  let dLen = d.len
  var i = dLen
  d.setLen(dLen + s.len*8 div 5)  # codes are at least 5 bits
  while true:
    while nbits <= 56 and pos < s.len:
      bits = bits or (s[pos].uint64 shl (56 - nbits))
      inc pos
      inc(nbits, 8)
    let e = lut[bits shr (64 - lutBits)]
    if e.len > 0 and e.len.int <= nbits:
      sym = e.sym.int
      L = e.len.int
    elif e.len == 0 and decodeLong(bits, nbits, sym, L):
      discard
    else:
      break
    d[i] = sym.char
    inc i
    bits = bits shl L
    dec(nbits, L)
  # the rest is padding; it must be
  # the EOS prefix (ones), up to 7 bits
  if nbits > 7 or (nbits > 0 and bits shr (64 - nbits) != (1'u64 shl nbits) - 1):
    return -1
  d.setLen(i)
  result = i - dLen

when isMainModule:
  block:
    echo "Test some codes"
    let hc = @[
      byte 0b11111111, 0b11000111,
      0b11111111, 0b11111101,
      0b10001111]
    var d = ""
    doAssert(hcdecode(hc, d) != -1)
    doAssert(d == "" & char(0) & char(1))
  block:
    echo "Test EOS is an error"
    var d = ""
    doAssert(hcdecode(@[byte 0xff, 0xff, 0xff, 0xff], d) == -1)
  block:
    echo "Test padding longer than 7 bits is an error"
    var d = ""
    doAssert(hcdecode(@[byte 0b00011111, 0b11111111], d) == -1)
  block:
    echo "Test padding not EOS prefix is an error"
    var d = ""
    doAssert(hcdecode(@[byte 0b00011010], d) == -1)
