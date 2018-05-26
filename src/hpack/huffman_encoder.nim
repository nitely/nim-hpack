import huffman_data

# todo: align + copy bytes? but chars
#       are usually < a single byte, so meh
proc hcencode*(s: string, e: var seq[byte]) =
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
      let b = if (co and k) > 0'u32: 1'u8 else: 0'u8
      e[i] += b shl (7-j)
      j = (j+1) and 7
      k = k shr 1
      i = if j == 0: i+1 else: i
  # padding
  while j > 0:
    e[i] += 1'u8 shl (7-j)
    j = (j+1) and 7
    i = if j == 0: i+1 else: i
  e.setLen(i)

when isMainModule:
  import huffman_decoder

  block:
    var
      e = newSeq[byte]()
      s = ""
    hcencode("a", e)
    doAssert hcdecode(e, s) != -1
    doAssert s == "a"
  block:
    var
      e = newSeq[byte]()
      s = ""
    for c in 0'u8.char .. 255'u8.char:
      e.setLen(0)
      s.setLen(0)
      hcencode("" & c, e)
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
        hcencode("" & c & c2, e)
        doAssert hcdecode(e, s) != -1
        doAssert s == "" & c & c2
  block:
    var
      e = newSeq[byte]()
      s = ""
      res = ""
    for c in 0'u8.char .. 255'u8.char:
      s.add(c)
    hcencode(s, e)
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
    hcencode(s, e)
    doAssert hcdecode(e, res) != -1
    doAssert s == res
