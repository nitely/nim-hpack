## HPACK encoder

import
  headers_data,
  huffman_encoder,
  hcollections

export hcollections

proc `==`(a, b: openArray[char]): bool {.inline.} =
  result = true
  if a.len != b.len:
    return false
  # todo: memcmp?
  var i = 0
  while i < a.len:
    if a[i] != b[i]:
      return false
    inc i

proc intencode(x: int, n: int, s: var seq[byte]): int =
  ## Encode using N-bit prefix.
  ## Return number of octets.
  ## First byte's 2^N bit is set for convenience
  # todo: add option to not set 2^N bit
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

proc strencode(x: openArray[char], s: var seq[byte], huffman: bool): int =
  result = 0
  if huffman:
    inc(result, intencode(hcencodeLen(x), 7, s))
    inc(result, hcencode(x, s))
  else:
    let sLen = s.len
    inc(result, intencode(x.len, 7, s))
    s[sLen] = s[sLen] and (1 shl 7)-1  # clear 2^N bit
    # todo: memcopy
    inc(result, x.len)
    var i = s.len
    s.setLen(s.len+x.len)
    for c in x:
      s[i] = c.uint8
      inc i

type
  HeaderRepr = enum
    rprIndexed
    rprIncIndexing
    rprNoIndexing
    rprNeverIndexed

# proc litencode

proc findInTable(s: openArray[char], dh: DynHeaders): int =
  ## Find a header name in table
  result = -1
  # todo: check if min hash is faster
  for i, h in headersTable.pairs:
    if s == h[0]:
      result = i
      return
  for i, hb in dh.pairs:
    if cmp(dh, hb.n, s):
      result = headersTable.len+i
      return

proc cmpTableValue(s: openArray[char], dh: DynHeaders, i: int): bool =
  assert i > 0
  let idyn = i-headersTable.len
  if i < headersTable.len:
    return s == headersTable[i][1]
  elif idyn < dh.len:
    return cmp(dh, dh[idyn].v, s)
  else:
    assert false

type
  Store = enum
    stoYes
    stoNo
    stoNever

proc hencode*(
    h, v: openArray[char],
    dh: var DynHeaders,
    s: var seq[byte],
    store = stoNo,
    huffman = false): int =
  let hidx = findInTable(h, dh)
  # Indexed
  if hidx != -1 and cmpTableValue(v, dh, hidx):
    result = intencode(hidx+1, 7, s)
    return
  case store
  # incremental indexing
  of stoYes:
    if hidx != -1:
      result = intencode(hidx+1, 6, s)
      inc(result, strencode(v, s, huffman))
    else:
      result = intencode(0, 6, s)
      inc(result, strencode(h, s, huffman))
      inc(result, strencode(v, s, huffman))
    dh.add(h, v)
  # without indexing or
  of stoNo:
    if hidx != -1:
      let sLen = s.len
      result = intencode(hidx+1, 4, s)
      s[sLen] = s[sLen] and (1 shl 4)-1  # clear 2^N bit
      inc(result, strencode(v, s, huffman))
    else:
      let sLen = s.len
      result = intencode(0, 4, s)
      s[sLen] = s[sLen] and (1 shl 4)-1  # clear 2^N bit
      inc(result, strencode(h, s, huffman))
      inc(result, strencode(v, s, huffman))
  # never indexed
  of stoNever:
    if hidx != -1:
      result = intencode(hidx+1, 4, s)
      inc(result, strencode(v, s, huffman))
    else:
      result = intencode(0, 4, s)
      inc(result, strencode(h, s, huffman))
      inc(result, strencode(v, s, huffman))

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

  proc toBytes(s: seq[uint16]): seq[byte] =
    result = newSeqOfCap[byte](len(s) * 2)
    for b in s:
      result.add(byte(b shr 8))
      result.add(byte(b and 0xff))

  block:
    echo "Test Literal Header Field with Indexing"
    var
      dhe = initDynHeaders(256, 16)
      ic = newSeq[byte]()
      expected = @[
        0x400a'u16, 0x6375, 0x7374, 0x6f6d,
        0x2d6b, 0x6579, 0x0d63, 0x7573,
        0x746f, 0x6d2d, 0x6865, 0x6164, 0x6572].toBytes
    doAssert hencode(
      "custom-key", "custom-header", dhe, ic, store = stoYes) == expected.len
    doAssert ic == expected
    doAssert $dhe == "custom-key: custom-header\r\L"
