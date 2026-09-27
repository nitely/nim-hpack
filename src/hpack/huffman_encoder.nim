## Huffman encoder.
##
## Codes are appended to a left aligned 64-bit
## accumulator. After every code the accumulator is
## stored unconditionally and its whole bytes are
## consumed, so there are no data dependent branches.

import ./huffman_data
import ./utils

func hcencodeLen*(s: openArray[char]): int {.inline.} =
  ## Return the length in bytes of
  ## the huffman encoded string
  var bitsLen = 0
  for c in s:
    inc(bitsLen, hcCodes[c.ord].len.int)
  result = (bitsLen + 7) shr 3

# Indices in the hot loop are guarded by construction
{.push checks: off.}

func hcencode*(s: openArray[char], e: var seq[byte]): int =
  ## Huffman encode ``s`` and append it to ``e``.
  ## Return the number of appended bytes
  let eLen = e.len
  # codes are at most 30 bits, so 4 bytes
  # per char + 8 bytes of store slack
  e.setLen(eLen + s.len*4 + 8)
  var
    acc = 0'u64  # left aligned; the top n bits are valid
    n = 0
    i = eLen
  for c in s:
    let code = hcCodes[c.ord]
    # n <= 7, and code.len <= 30
    acc = acc or (code.code.uint64 shl (64 - n - code.len.int))
    inc n, code.len.int
    store64BE(e, i, acc)
    let k = n shr 3
    inc i, k
    acc = acc shl (k * 8)
    n = n and 7
  if n > 0:
    # pad with the EOS prefix (ones)
    acc = acc or (not 0'u64 shr n)
    e[i] = uint8(acc shr 56)
    inc i
  e.setLen(i)
  result = i - eLen

{.pop.}

when isMainModule:
  import huffman_decoder

  block:
    var
      e = newSeq[byte]()
      s = ""
    doAssert hcencode("a", e) == "a".hcencodeLen
    doAssert hcdecode(e, s) != -1
    doAssert s == "a"
  block:
    var
      e = newSeq[byte]()
      s = ""
    for c in 0'u8.char .. 255'u8.char:
      e.setLen(0)
      s.setLen(0)
      doAssert hcencode("" & c, e) == hcencodeLen("" & c)
      doAssert hcdecode(e, s) != -1
      doAssert s == "" & c
  block:
    var
      e = newSeq[byte]()
      s = ""
    for c in 0'u8.char .. 255'u8.char:
      for c2 in 0'u8.char .. 255'u8.char:
        e.setLen(0)
        s.setLen(0)
        doAssert hcencode("" & c & c2, e) == hcencodeLen("" & c & c2)
        doAssert hcdecode(e, s) != -1
        doAssert s == "" & c & c2
  block:
    var
      e = newSeq[byte]()
      s = ""
      res = ""
    for c in 0'u8.char .. 255'u8.char:
      s.add(c)
    doAssert hcencode(s, e) == s.hcencodeLen
    doAssert hcdecode(e, res) != -1
    doAssert s == res
  block:
    var
      e = newSeq[byte]()
      s = ""
      res = ""
    for c in 'a' .. 'z':
      s.add(c)
    for c in 'A' .. 'Z':
      s.add(c)
    for c in '0' .. '9':
      s.add(c)
    doAssert hcencode(s, e) == s.hcencodeLen
    doAssert hcdecode(e, res) != -1
    doAssert s == res
