import huffman_data

type
  State = enum
    stNxt
    stSym
    stFlags

proc contains(fs: uint8, f: HcFlag): bool =
  result = (fs.int and f.ord) != 0

proc hcdecode*(s: seq[byte]): string =
  result = newString(32)
  var
    state = [0'u8, 0, 0]
    i = 0
  for b in s:
    state = hcTable[state[stNxt.ord]][b shr 4]
    if hcfContinue notin state[stFlags.ord]:
      raise newException(ValueError, "Invalid Huffman code")
    if hcfSym in state[stFlags.ord]:
      if i > result.high:
        result.setLen(len(result) * 2)
      result[i] = state[stSym.ord].char
      inc i
    state = hcTable[state[stNxt.ord]][b and 0x0f]
    if hcfContinue notin state[stFlags.ord]:
      raise newException(ValueError, "Invalid Huffman code")
    if hcfSym in state[stFlags.ord]:
      if i > result.high:
        result.setLen(len(result) * 2)
      result[i] = state[stSym.ord].char
      inc i
  if hcfDone notin state[stFlags.ord]:
    raise newException(ValueError, "Invalid Huffman code")
  result.setLen(i)

when isMainModule:
  block:
    echo "Test some codes"
    let hc = @[
      byte(0b11111111), byte(0b11000111),
      byte(0b11111111), byte(0b11111101),
      byte(0b10001111)]
    doAssert(hcdecode(hc) == "" & char(0) & char(1))
