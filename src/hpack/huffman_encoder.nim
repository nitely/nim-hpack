import huffman_data

proc hcencodeLen*(s: openArray[char]): Natural {.inline.} =
  result = 0
  var sLen = 0
  for c in s:
    inc(sLen, hcDecTable[c.ord][1].int)
  result = sLen div 8
  result += (sLen mod 8 != 0).int

# todo: align + copy bytes? but chars
#       are usually < a single byte, so meh
proc hcencode*(s: openArray[char], e: var seq[byte]): Natural {.inline.} =
  result = e.len
  var
    i = e.len
    j = 0
    k = 0'u32
  e.setLen(e.len+s.len*4)
  for c in s:
    assert c.ord < 256
    let
      code = hcDecTable[c.ord]
      co = code[0]
      coLen = code[1]
    k = 1'u32 shl (coLen-1)
    while k > 0'u32:
      e[i] += ((co and k) > 0'u32).uint8 shl (7-j)
      j = (j+1) and 7
      k = k shr 1
      i += (j == 0).int
  # padding
  while j > 0:
    e[i] += 1'u8 shl (7-j)
    j = (j+1) and 7
    i += (j == 0).int
  e.setLen(i)
  result = i - result

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
