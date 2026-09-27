import ./huffman_data

proc hcencodeLen*(s: openArray[char]): Natural {.inline.} =
  result = 0
  var sLen = 0
  for c in s:
    inc(sLen, hcDecTable[c.ord][1].int)
  result = sLen div 8
  result += (sLen mod 8 != 0).int

proc hcencode*(s: openArray[char], e: var seq[byte]): Natural {.inline.} =
  let eLen = e.len
  # codes are at most 30 bits (4 bytes)
  e.setLen(eLen+s.len*4)
  var
    acc = 0'u64  # only the low n bits are valid
    n = 0
    i = eLen
  for c in s:
    let code = hcDecTable[c.ord]
    acc = (acc shl code[1]) or code[0]
    inc(n, code[1].int)
    if n >= 32:
      dec(n, 32)
      let x = acc shr n
      e[i] = uint8((x shr 24) and 0xff)
      e[i+1] = uint8((x shr 16) and 0xff)
      e[i+2] = uint8((x shr 8) and 0xff)
      e[i+3] = uint8(x and 0xff)
      inc(i, 4)
  # pad with ones (EOS prefix)
  let pad = (8 - (n and 7)) and 7
  acc = (acc shl pad) or ((1'u64 shl pad) - 1)
  inc(n, pad)
  while n > 0:
    dec(n, 8)
    e[i] = uint8((acc shr n) and 0xff)
    inc i
  e.setLen(i)
  result = i - eLen

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
