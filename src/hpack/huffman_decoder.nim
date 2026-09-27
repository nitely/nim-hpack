## Huffman decoder.
##
## The input is read through a 64-bit bit buffer.
## The next ``lutBits`` bits index a lookup table that
## yields up to two decoded symbols at once. Codes longer
## than ``lutBits`` are rare in practice; they are
## decoded using the canonical code properties.

import ./huffman_data
import ./utils

const
  lutBits = 12
  maxCodeLen = 30
  minCodeLen = 5

type
  Canonical = object
    ## Codes of the same length are consecutive
    ## integers ordered by symbol (RFC 7541 Appendix B)
    first: array[maxCodeLen+1, uint32]
    count: array[maxCodeLen+1, uint32]
    offset: array[maxCodeLen+1, uint16]
    syms: array[hcCodes.len, uint16]
  LutEntry = object
    ## Byte fields so the decode loop reads
    ## them without shifting and masking
    len: uint8  # total length of decoded codes
    nsyms: uint8  # number of decoded symbols (0 to 2)
    syms: array[2, char]

func buildCanonical(): Canonical =
  var n = 0
  for L in 1 .. maxCodeLen:
    result.offset[L] = n.uint16
    result.first[L] = uint32.high
    for sym in 0 .. hcCodes.len-1:
      if hcCodes[sym].len.int != L:
        continue
      if result.count[L] == 0:
        result.first[L] = hcCodes[sym].code
      doAssert hcCodes[sym].code == result.first[L] + result.count[L]
      result.syms[n] = sym.uint16
      inc result.count[L]
      inc n
  doAssert n == hcCodes.len

const canon = buildCanonical()

func decodeCode(
  bits: uint64, minLen, maxLen: int, sym, L: var int
): bool {.inline.} =
  ## Decode the code prefixing the left aligned ``bits``.
  ## Return false if no code of length
  ## ``minLen .. maxLen`` matches.
  for i in minLen .. maxLen:
    let idx = uint32(bits shr (64 - i)) - canon.first[i]
    if idx < canon.count[i]:
      sym = canon.syms[canon.offset[i].int + idx.int].int
      L = i
      return true
  return false

func buildLut(): array[1 shl lutBits, LutEntry] =
  for i in 0 .. result.len-1:
    var
      e = LutEntry()
      sym, L = 0
    while e.nsyms < 2:
      let bits = (i.uint64 shl (64 - lutBits)) shl e.len
      if not decodeCode(bits, minCodeLen, lutBits-e.len.int, sym, L):
        break
      doAssert sym < hcEos
      e.syms[e.nsyms] = sym.char
      inc e.len, L
      inc e.nsyms
    result[i] = e

const lut = buildLut()

# Indices in the hot loop are guarded by construction
{.push checks: off.}

func hcdecodeMaxLen*(n: int): int {.inline.} =
  ## Return the buffer length ``hcdecode``
  ## needs to decode ``n`` bytes
  # +1 because two symbols are written
  # unconditionally for every lookup
  (n * 8) div minCodeLen + 1

func hcdecode*(s: openArray[byte], d: var openArray[char]): int =
  ## Huffman decoder.
  ## Decode ``s`` into the start of ``d``.
  ## ``d.len`` must be at least ``hcdecodeMaxLen(s.len)``.
  ## Return length of the decoded string,
  ## or -1 on error.
  result = 0
  if s.len == 0:
    return
  doAssert d.len >= hcdecodeMaxLen(s.len)
  var
    bits = 0'u64  # left aligned
    nbits = 0
    pos = 0
    i = 0
    sym, L = 0
  while true:
    if pos + 8 <= s.len:
      bits = bits or (load64BE(s, pos) shr nbits)
      inc pos, (63 - nbits) shr 3
      nbits = nbits or 56
    else:
      while nbits <= 56 and pos < s.len:
        bits = bits or (s[pos].uint64 shl (56 - nbits))
        inc pos
        inc nbits, 8
    if nbits < lutBits:
      break
    # consume the buffer before refilling
    while nbits >= lutBits:
      let e = lut[bits shr (64 - lutBits)]
      if e.nsyms > 0:
        d[i] = e.syms[0]
        d[i+1] = e.syms[1]
        inc i, e.nsyms.int
        bits = bits shl e.len
        dec nbits, e.len.int
        continue
      if nbits < maxCodeLen and pos < s.len:
        break  # refill
      if not decodeCode(bits, lutBits+1, min(nbits, maxCodeLen), sym, L) or
          sym == hcEos:
        return -1
      d[i] = sym.char
      inc i
      bits = bits shl L
      dec nbits, L
  # less than lutBits left;
  # bits past nbits are zero
  while nbits >= minCodeLen:
    let e = lut[bits shr (64 - lutBits)]
    if e.nsyms == 0:
      break
    let len1 = hcCodes[e.syms[0].ord].len.int
    if len1 > nbits:
      break
    d[i] = e.syms[0]
    inc i
    bits = bits shl len1
    dec nbits, len1
  # padding must be the EOS prefix, up to 7 bits
  if nbits > 7:
    return -1
  if nbits > 0 and (bits shr (64 - nbits)) != (1'u64 shl nbits) - 1:
    return -1
  result = i

{.pop.}

func hcdecode*(s: openArray[byte], d: var string): int =
  ## Huffman decoder.
  ## Return length of the decoded string.
  ## Return -1 on error.
  ## Decoded string is appended to param ``d``.
  ## If there's an error, ``d`` is left unchanged
  let dLen = d.len
  d.setLen(dLen + hcdecodeMaxLen(s.len))
  result = hcdecode(s, d.toOpenArray(dLen, d.len-1))
  d.setLen(dLen + max(result, 0))

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
    let hc = @[byte 0xff, 0xff, 0xff, 0xff]
    var d = ""
    doAssert(hcdecode(hc, d) == -1)
  block:
    echo "Test padding longer than 7 bits is an error"
    # 'a' (00011) + 11 bits of ones
    let hc = @[byte 0b00011111, 0b11111111]
    var d = ""
    doAssert(hcdecode(hc, d) == -1)
  block:
    echo "Test padding not EOS prefix is an error"
    # 'a' (00011) + 010
    let hc = @[byte 0b00011010]
    var d = ""
    doAssert(hcdecode(hc, d) == -1)
