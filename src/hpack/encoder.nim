
import huffman_data

#[
if I < 2^N - 1, encode I on N bits
   else
       encode (2^N - 1) on N bits
       I = I - (2^N - 1)
       while I >= 128
            encode (I % 128 + 128) on 8 bits
            I = I / 128
       encode I on 8 bits
]#

#[
proc hcencode2(s: string): seq[byte] =
  let hc = [
    [0x1ff8, 13],
    [0x7fffd8, 23],
    # ...
  ]
  result = newSeq[byte](s.len*4)
  var i = 0
  for c in s:
    let code = hc[c.ord]
    var n = code[0]
    var len = code[1]
    len = max(0, code[1]-shf)
    result[i] += (n shr len) and 0xff
    inc i
    n = n and (len shl 1) - 1
    shf = len and 7
    if len > 24:
      result[i] = (n shr 24) and 0xff
      result[i+1] = (n shr 16) and 0xff
      result[i+2] = (n shr 8) and 0xff
      result[i+3] = (n shl shf) and 0xff
      inc(i, 3)
    elif len > 16:
      result[i] = (n shr 16) and 0xff
      result[i+1] = (n shr 8) and 0xff
      result[i+2] = (n shl shf) and 0xff
      inc(i, 2)
    elif len > 8:
      result[i] = (n shr 8) and 0xff
      result[i+1] = (n shl shf) and 0xff
      inc i
    elif len > 0:
      result[i] = n shl shf
    else:
      dec i
    if shf == 0:
      inc i
]#

proc hcencode(s: string): seq[byte] =
  # todo: align + copy one byte at a time?
  #       but meh, visible char codes are small
  result = newSeq[byte](s.len*4)
  var
    i = 0
    j = 0
    k = 0'u32
  for c in s:
    let code = hcDecTable[c.ord]
    k = 1'u32 shl (code[1]-1)
    while k > 0'u32:
      let b = if (code[0] and k) > 0'u32: 1'u8 else: 0'u8
      result[i] += b shl (7-j)
      j = (j+1) and 7
      k = k shr 1
      i = if j == 0: i+1 else: i
  if k == 0'u32 and j == 0:
    result.setLen(i)
  else:
    result.setLen(i+1)
  while j > 0:
    result[i] += 1'u8 shl (7-j)
    j = (j+1) and 7

when isMainModule:
  import huffman_decoder

  block:
    var s = ""
    doAssert hcdecode(hcencode("a"), s) != -1
    doAssert s == "a"
  block:
    var s = ""
    for c in 0'u8.char .. 255'u8.char:
      doAssert hcdecode(hcencode("" & c), s) != -1
      doAssert s == "" & c
      s.setLen(0)
  block:
    var s = ""
    for c in 0'u8.char .. 255'u8.char:
      for c2 in 0'u8.char .. 255'u8.char:
        doAssert hcdecode(hcencode("" & c & c2), s) != -1
        doAssert s == "" & c & c2
        s.setLen(0)
  block:
    var s = ""
    var res = ""
    for c in 0'u8.char .. 255'u8.char:
      s.add(c)
    doAssert hcdecode(hcencode(s), res) != -1
    doAssert s == res
  block:
    var s = ""
    var res = ""
    for c in 'a' .. 'z':
      s.add(c)
    for c in 'A' .. 'Z':
      s.add(c)
    for c in '0' .. '9':
      s.add(c)
    doAssert hcdecode(hcencode(s), res) != -1
    doAssert s == res
