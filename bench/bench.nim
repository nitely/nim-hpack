## HPACK benchmarks.
##
## Run with: nimble bench
##
## Uses the hpack-test-case stories in tests/testdata.
## Every benchmark replays whole stories (fresh dynamic
## table per story) so dynamic table behavior is exercised.

import std/[os, json, monotimes, times, algorithm, strutils]

import ../src/hpack
import ../src/hpack/[huffman_encoder, huffman_decoder, utils]

const testDataDir = currentSourcePath.parentDir.parentDir / "tests" / "testdata"

type
  Case = object
    wire: seq[byte]
    headers: seq[(string, string)]
    tableSize: int
  Story = seq[Case]

proc loadStories(name: string): seq[Story] =
  var paths: seq[string]
  for w in walkDir(testDataDir / name):
    paths.add w.path
  paths.sort()
  for path in paths:
    var story: Story
    for c in parseJson(readFile(path))["cases"]:
      var cs = Case(tableSize: -1)
      for b in c{"wire"}.getStr().parseHexStr():
        cs.wire.add b.byte
      for hs in c["headers"]:
        for n, v in pairs hs:
          cs.headers.add (n, v.getStr())
      if "header_table_size" in c:
        cs.tableSize = c["header_table_size"].getInt(-1)
      story.add cs
    result.add story

var sink: int

let filter = if paramCount() > 0: paramStr(1) else: ""

template measure(name: string, bytesPerIter, headersPerIter: int, body: untyped) =
  if filter.len == 0 or filter in name:
    when defined(profileOnce):
      # single-pass mode for running under callgrind
      for _ in 0 ..< 20:
        body
    else:
      # warmup + pick an iteration count targeting ~0.5s per sample
      var iters = 1
      while true:
        let t0 = getMonoTime()
        for _ in 0 ..< iters:
          body
        if (getMonoTime() - t0).inMilliseconds >= 100:
          iters = max(1, iters * 5)
          break
        iters *= 2
      var best = int64.high
      for _ in 0 ..< 5:
        let t0 = getMonoTime()
        for _ in 0 ..< iters:
          body
        best = min(best, (getMonoTime() - t0).inNanoseconds)
      let nsPerIter = best.float / iters.float
      let mbs = bytesPerIter.float / nsPerIter * 1e9 / (1024 * 1024)
      let nsPerHeader = nsPerIter / headersPerIter.float
      echo alignLeft(name, 40),
        align(formatFloat(mbs, ffDecimal, 1), 10), " MB/s",
        align(formatFloat(nsPerHeader, ffDecimal, 1), 10), " ns/header"

proc benchDecode(name: string) =
  let stories = loadStories(name)
  var wireLen, nHeaders = 0
  for st in stories:
    for c in st:
      wireLen += c.wire.len
      nHeaders += c.headers.len
  var dh = initDynHeaders(4096)
  var ss = ""
  var bb = newSeq[HBounds]()
  measure("decode " & name, wireLen, nHeaders):
    for st in stories:
      dh.clear()
      dh.setSize(4096)
      for c in st:
        if c.tableSize >= 0:
          dh.setSize(c.tableSize)
        ss.setLenUninit2 0
        bb.setLenUninit2 0
        hdecodeAll(c.wire, dh, ss, bb)
        sink += ss.len

proc benchEncode(name: string, store: Store, huffman: bool) =
  let stories = loadStories(name)
  var rawLen, nHeaders = 0
  for st in stories:
    for c in st:
      nHeaders += c.headers.len
      for (n, v) in c.headers:
        rawLen += n.len + v.len
  var dh = initDynHeaders(4096)
  var s = newSeq[byte]()
  measure("encode " & name & " " & $store & " huffman=" & $huffman, rawLen, nHeaders):
    for st in stories:
      dh.clear()
      dh.setSize(4096)
      for c in st:
        s.setLenUninit2 0
        for (n, v) in c.headers:
          hencode(n, v, dh, s, store, huffman)
        sink += s.len

proc benchHuffman() =
  let stories = loadStories("raw-data")
  var strs: seq[string]
  var rawLen = 0
  for st in stories:
    for c in st:
      for (n, v) in c.headers:
        strs.add v
        rawLen += v.len
  var encoded: seq[seq[byte]]
  var encLen = 0
  for x in strs:
    var e = newSeq[byte]()
    discard hcencode(x, e)
    encLen += e.len
    encoded.add e
  var e = newSeq[byte]()
  measure("huffman encode (raw bytes)", rawLen, strs.len):
    for x in strs:
      e.setLenUninit2 0
      sink += hcencode(x, e)
  var d = ""
  measure("huffman decode (encoded bytes)", encLen, strs.len):
    for x in encoded:
      d.setLenUninit2 0
      sink += hcdecode(x, d)

benchHuffman()
benchDecode("nghttp2")
benchDecode("go-hpack")
benchDecode("haskell-http2-linear-huffman")
benchDecode("haskell-http2-naive")
benchDecode("swift-nio-hpack-plain-text")
benchEncode("raw-data", stoYes, true)
benchEncode("raw-data", stoYes, false)
benchEncode("raw-data", stoNo, true)
benchEncode("raw-data", stoNo, false)
echo "sink: ", sink
