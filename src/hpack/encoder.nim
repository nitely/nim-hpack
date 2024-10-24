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
    # todo: memcopy
    inc(result, x.len)
    var i = s.len
    s.setLen(s.len+x.len)
    for c in x:
      s[i] = c.uint8
      inc i

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

proc cmpTableValue(
  s: openArray[char],
  dh: DynHeaders,
  i: Natural
): bool {.inline.} =
  let idyn = i-headersTable.len
  if i < headersTable.len:
    return s == headersTable[i][1]
  elif idyn < dh.len:
    return cmp(dh, dh[idyn].v, s)
  else:
    doAssert false

proc findInTable(h, v: openArray[char], dh: DynHeaders): int {.inline.} =
  ## Find a header name in table
  # note linear search here is fine;
  # for a 4KB table, there should be <100 entries;
  # encoding is controlled by user, and they can
  # disable indexing if needed
  var first = -1
  # todo: check if min hash is faster
  for i, h0 in headersTable.pairs:
    if h != h0[0]:
      continue
    if cmpTableValue(v, dh, i):
      return i
    if first == -1:
      first = i
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
