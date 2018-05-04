import huffman_data

type
  State = enum
    stNxt
    stSym
    stFlags

proc contains(fs: uint8, f: HcFlag): bool =
  result = (fs.int and f.ord) != 0

template consume(bits) {.dirty.} =
  state = hcTable[state[stNxt.ord]][bits]
  if hcfContinue notin state[stFlags.ord]:
    result = -1
    return
  if hcfSym in state[stFlags.ord]:
    d[i] = state[stSym.ord].char
    inc i
    inc result

proc hcdecode*(s: openArray[byte], d: var string): int =
  ## Huffman decoder.
  ## Return length of the decoded string.
  ## Return -1 on error.
  ## Decoded string is appended to param ``d``.
  ## If there's an error, ``d``
  ## may contain a partial decoded string
  result = 0
  var
    state = [0'u8, 0, 0]
    i = d.len
  d.setLen(d.len + s.len * 2)
  for b in s:
    consume(b shr 4)
    consume(b and 0x0f)
  if hcfDone notin state[stFlags.ord]:
    result = -1
    return
  d.setLen(i)

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
