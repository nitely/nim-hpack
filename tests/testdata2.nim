
from std/strutils import parseHexStr
import std/os
import std/json

import ../src/hpack

const testDataBaseDir = "tests/testdata/"

proc testCase(theDir: string) =
  echo theDir
  let dir = testDataBaseDir & theDir
  var paths: seq[string] = @[]
  for w in walkDir(dir, relative = true):
    paths.add w.path
  #echo paths
  var checked = 0
  for fname in paths:
    let jsonNode = parseJson(readFile(dir & "/" & fname))
    var headersEnc = initDynHeaders(4096)
    var headersDec = initDynHeaders(4096)
    for cases in jsonNode["cases"]:
      var headers = ""
      for hs in cases["headers"]:
        for n, v in pairs hs:
          headers.add n
          headers.add ": "
          headers.add v.getStr()
          headers.add "\r\n"
      let wire = cases["wire"].getStr()
      var wireBytes = newSeq[byte]()
      for c in wire.parseHexStr():
        wireBytes.add c.byte
      var ds = initDecodedStr()
      hdecodeAll(wireBytes, headersDec, ds)
      #echo $ds
      doAssert $ds == headers, fname & " wire: " & wire
      inc checked
  doAssert checked == 3384

proc testCase2(theDir: string, store: Store, huffman: bool) =
  echo theDir
  let dir = testDataBaseDir & theDir
  var paths: seq[string] = @[]
  for w in walkDir(dir, relative = true):
    paths.add w.path
  #echo paths
  var checked = 0
  for fname in paths:
    let jsonNode = parseJson(readFile(dir & "/" & fname))
    var headersEnc = initDynHeaders(4096)
    var headersDec = initDynHeaders(4096)
    for cases in jsonNode["cases"]:
      var ic = newSeq[byte]()
      var headers = ""
      for hs in cases["headers"]:
        for n, v in pairs hs:
          headers.add n
          headers.add ": "
          headers.add v.getStr()
          headers.add "\r\n"
          discard hencode(
            n, v.getStr(), headersEnc, ic, store = store, huffman = huffman
          )
      var ds = initDecodedStr()
      hdecodeAll(ic, headersDec, ds)
      #echo headers
      #echo $ds
      #echo headersDec.s
      #echo headersEnc.s
      doAssert $ds == headers
      inc checked
  doAssert checked == 3384

testCase "haskell-http2-linear"
testCase "haskell-http2-linear-huffman"
testCase "haskell-http2-naive"
testCase "haskell-http2-naive-huffman"
testCase "haskell-http2-static"
testCase "haskell-http2-static-huffman"
testCase2("raw-data", store = stoNo, huffman = true)
testCase2("raw-data", store = stoNo, huffman = false)
testCase2("raw-data", store = stoNever, huffman = true)
testCase2("raw-data", store = stoNever, huffman = false)
testCase2("raw-data", store = stoYes, huffman = true)
testCase2("raw-data", store = stoYes, huffman = false)
echo "ok"