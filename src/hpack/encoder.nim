## HPACK encoder

import
  ./headers_data,
  ./huffman_encoder,
  ./hcollections,
  ./utils,
  ./exceptions

export
  hcollections,
  exceptions

template ones(n: untyped): uint8 =
  assert n >= 1 and n <= 8
  (1'u8 shl n) - 1

type
  NbitPref = range[1 .. 8]

proc intencode(x: Natural, n: NbitPref, s: var seq[byte]): int {.inline.} =
  ## Encode using N-bit prefix.
  ## Return number of octets.
  ## First byte's 2^N bit is set for convenience
  # todo: add option to not set 2^N bit
  result = 1
  if x.uint < n.ones:
    s.add(x.uint8 or (1'u8 shl n))
    return
  s.add(n.ones or (1'u8 shl n))
  var x = x.uint - n.ones
  # leading 1-bit means continuation
  while x > 7.ones.uint:
    s.add((x and 7.ones).uint8 or 1'u8 shl 7)
    x = x shr 7
    inc result
  s.add x.uint8
  inc result

proc strencode(
  x: openArray[char],
  s: var seq[byte],
  huffman: bool
): Natural {.inline.} =
  result = 0
  if huffman:
    inc(result, intencode(hcencodeLen(x), 7, s))
    inc(result, hcencode(x, s))
  else:
    let sLen = s.len
    inc(result, intencode(x.len, 7, s))
    s[sLen] = s[sLen] and 7.ones  # clear 2^N bit
    inc(result, x.len)
    if x.len > 0:
      let L = s.len
      s.setLen(L+x.len)
      copyMem(addr s[L], unsafeAddr x[0], x.len)

proc litencode(
  h, v: openArray[char],
  s: var seq[byte],
  hidx: int,
  np: NbitPref,
  huffman: bool
): int {.inline.} =
  ## Encode literal header field:
  ## with incremental indexing,
  ## without indexing, or
  ## never indexed.
  ## Return number of consumed octets
  result = intencode(hidx+1, np, s)
  if hidx == -1:
    inc(result, strencode(h, s, huffman))
  inc(result, strencode(v, s, huffman))

type
  StaticName = object
    ## Static table entries with the same name
    ## are next to each other
    hash: uint32
    first, count: int8

const staticIndexLen = 128  # power of 2; ~2x the distinct names

func buildStaticIndex(): array[staticIndexLen, StaticName] =
  for x in mitems result:
    x.first = -1
  var i = 0
  while i < headersTable.len:
    let name = headersTable[i][0]
    var count = 0
    while i+count < headersTable.len and headersTable[i+count][0] == name:
      inc count
    for x in result:
      doAssert x.first == -1 or headersTable[x.first][0] != name
    let h = strhash(name)
    var slot = h.int and (staticIndexLen-1)
    while result[slot].first != -1:
      slot = (slot+1) and (staticIndexLen-1)
    result[slot] = StaticName(hash: h, first: i.int8, count: count.int8)
    inc(i, count)

const staticIndex = buildStaticIndex()

func findStatic(
  h, v: openArray[char], hh: uint32, nameIdx: var int
): int {.inline.} =
  ## Return the index of the static table entry matching
  ## the name and value, or ``-1``. ``nameIdx`` is set to
  ## the first entry matching the name, or ``-1``
  result = -1
  nameIdx = -1
  var slot = hh.int and (staticIndexLen-1)
  while staticIndex[slot].first != -1:
    let x = staticIndex[slot]
    if x.hash == hh and eqStr(headersTable[x.first][0], h):
      nameIdx = x.first
      for i in x.first.int ..< x.first.int+x.count.int:
        if eqStr(headersTable[i][1], v):
          return i
      return
    slot = (slot+1) and (staticIndexLen-1)

type
  Store* = enum
    stoYes
    stoNo
    stoNever

proc hencode*(
  h, v: openArray[char],
  dh: var DynHeaders,
  s: var seq[byte],
  store = stoYes,
  huffman = true
): Natural {.discardable, raises: [].} =
  let hh = strhash(h)
  var sNameIdx = -1
  let sIdx = findStatic(h, v, hh, sNameIdx)
  # Indexed
  if sIdx != -1:
    result = intencode(sIdx+1, 7, s)
    return
  let hv =
    if dh.len > 0 or store == stoYes: pairhash(hh, v)
    else: 0
  if dh.len > 0:
    let dIdx = dh.find(h, v, hv)
    if dIdx != -1:
      result = intencode(headersTable.len+dIdx+1, 7, s)
      return
  var hidx = sNameIdx
  if hidx == -1 and dh.len > 0:
    hidx = dh.findName(h, hh)
    if hidx != -1:
      inc(hidx, headersTable.len)
  case store
  # incremental indexing
  of stoYes:
    result = litencode(h, v, s, hidx, 6, huffman)
    dh.add(h, v, hh, hv)
  # without indexing or
  of stoNo:
    # todo: litencode for DRY-ness, needs clear bit
    if hidx != -1:
      let sLen = s.len
      result = intencode(hidx+1, 4, s)
      s[sLen] = s[sLen] and 4.ones  # clear 2^N bit
      inc(result, strencode(v, s, huffman))
    else:
      let sLen = s.len
      result = intencode(0, 4, s)
      s[sLen] = s[sLen] and 4.ones  # clear 2^N bit
      inc(result, strencode(h, s, huffman))
      inc(result, strencode(v, s, huffman))
  # never indexed
  of stoNever:
    result = litencode(h, v, s, hidx, 4, huffman)

proc signalDynTableSizeUpdate*(
  s: var seq[byte],
  size: Natural
): Natural {.discardable, raises: [].} =
  ## Add dynamic table size update
  ## field to the seq of bytes
  result = intencode(size, 5, s)

func encodeLastResize*(
  dh: var DynHeaders,
  s: var seq[byte]
): Natural {.discardable, raises: [].} =
  ## Add last dynamic table resize signal
  ## to ``s``
  doAssert dh.minSetSize <= dh.finalSetSize
  result = 0
  if dh.hasResized():
    result += signalDynTableSizeUpdate(s, dh.minSetSize)
  if dh.finalSetSize != dh.minSetSize:
    result += signalDynTableSizeUpdate(s, dh.finalSetSize)

when isMainModule:
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
