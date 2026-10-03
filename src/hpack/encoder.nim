## HPACK encoder

import
  ./headers_data,
  ./huffman_encoder,
  ./hcollections,
  ./exceptions

export
  hcollections,
  exceptions

template ones(n: untyped): uint8 =
  assert n >= 1 and n <= 8
  uint8((1.uint shl n) - 1 and 0xff)

template bit(n: untyped): uint8 =
  uint8((1.uint shl n) and 0xff)

type
  NbitPref = int8

proc intencode(x: Natural, n: NbitPref, s: var seq[byte]): int {.inline.} =
  ## Encode using N-bit prefix.
  ## Return number of octets.
  ## First byte's 2^N bit is set for convenience
  # todo: add option to not set 2^N bit
  result = 1
  if x.uint < n.ones:
    s.add(x.uint8 or n.bit)
    return
  s.add(n.ones or n.bit)
  var x = x.uint - n.ones
  # leading 1-bit means continuation
  while x > 7.ones.uint:
    s.add((x and 7.ones).uint8 or 1'u8 shl 7)
    x = x shr 7
    inc result
  s.add x.uint8
  inc result

{.push checks: off.}
func strcopy(
  x: var openArray[byte],
  y: openArray[char],
  xi, yi, xyLen: int
) {.inline, raises: [].} =
  assert x.len >= xi+xyLen
  assert y.len >= yi+xyLen
  for i in 0 ..< xyLen:
    x[xi+i] = byte(y[yi+i])
{.pop.}

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
    let L = s.len
    s.setLenUninit(L+x.len)
    strcopy(s, x, L, 0, x.len)

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

{.push checks: off.}
func strcmp(
  x, y: openArray[char]
): bool {.inline, raises: [].} =
  if x.len != y.len:
    return false
  var diff = 0'u8
  for i in 0 ..< x.len:
    diff = diff or (x[i].uint8 xor y[i].uint8)
  diff == 0
{.pop.}

proc cmpTableValue(
  s: openArray[char],
  dh: DynHeaders,
  i: Natural
): bool {.inline.} =
  let idyn = i-headersTable.len
  if i < headersTable.len:
    return strcmp(s, headersTable[i][1])
  elif idyn < dh.len:
    return cmp(dh, dh[idyn].v, s)
  else:
    doAssert false

func nameHash(s: openArray[char], seed: uint32): int {.inline.} =
  var h = seed
  for c in s:
    h = (h xor c.uint32) * 16777619'u32
  int(h shr 24)  # 256 slots

type StaticSlot = tuple[first, count: int8]

func buildStaticNames(): (uint32, array[256, StaticSlot]) =
  ## Perfect hash of the static table names. Entries
  ## with the same name are next to each other
  var seed = 2166136261'u32
  while true:
    var slots: array[256, StaticSlot]
    for x in mitems slots:
      x.first = -1
    var ok = true
    var i = 0
    while ok and i < headersTable.len:
      let slot = nameHash(headersTable[i][0], seed)
      ok = slots[slot].first == -1
      slots[slot] = (i.int8, 0'i8)
      while i < headersTable.len and
          headersTable[i][0] == headersTable[slots[slot].first][0]:
        inc slots[slot].count
        inc i
    if ok:
      return (seed, slots)
    inc seed

const (staticSeed, staticNames) = buildStaticNames()

proc findInTable(h, v: openArray[char], dh: DynHeaders): int {.inline.} =
  ## Find a header name in table
  # note linear search here is fine;
  # for a 4KB table, there should be <100 entries;
  # encoding is controlled by user, and they can
  # disable indexing if needed
  var first = -1
  let x = staticNames[nameHash(h, staticSeed)]
  if x.first != -1 and strcmp(h, headersTable[x.first][0]):
    first = x.first
    for i in x.first ..< x.first+x.count:
      if strcmp(v, headersTable[i][1]):
        return i
  let L = headersTable.len
  for i, hb in dh.pairs:
    if not cmp(dh, hb.n, h):
      continue
    if cmpTableValue(v, dh, L+i):
      return L+i
    if first == -1:
      first = L+i
  return first

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
  let hidx = findInTable(h, v, dh)
  # Indexed
  if hidx != -1 and cmpTableValue(v, dh, hidx):
    result = intencode(hidx+1, 7, s)
    return
  case store
  # incremental indexing
  of stoYes:
    result = litencode(h, v, s, hidx, 6, huffman)
    dh.add(h, v)
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
