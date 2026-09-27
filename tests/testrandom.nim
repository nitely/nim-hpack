## Randomized tests

import std/random

import ../src/hpack
import ../src/hpack/huffman_encoder
import ../src/hpack/huffman_decoder
import ../src/hpack/utils

var rng = initRand(42)

proc randStr(maxLen: int, alphabet = ""): string =
  result = newString(rng.rand(maxLen))
  for c in mitems result:
    c = if alphabet.len > 0: alphabet[rng.rand(alphabet.high)]
      else: rng.rand(255).char

block:
  echo "Test huffman roundtrip"
  for _ in 0 ..< 20_000:
    let s = randStr(300)
    var e = newSeq[byte]()
    let n = hcencode(s, e)
    doAssert n == e.len
    doAssert n == hcencodeLen(s)
    var d = ""
    doAssert hcdecode(e, d) == s.len
    doAssert d == s

block:
  echo "Test huffman decode random bytes"
  # valid input decodes uniquely, and the padding
  # is canonical, so it must encode back to the input
  var valid = 0
  for _ in 0 ..< 100_000:
    var e = newSeq[byte](rng.rand(6))
    for b in mitems e:
      b = rng.rand(255).byte
    var d = "prefix"
    let n = hcdecode(e, d)
    if n == -1:
      doAssert d == "prefix"
      continue
    inc valid
    doAssert d.len == "prefix".len + n
    var e2 = newSeq[byte]()
    discard hcencode(d.toOpenArray("prefix".len, d.len-1), e2)
    doAssert e2 == e
  doAssert valid > 1000

type ModelEntry = tuple[n, v: string]

proc modelSize(m: seq[ModelEntry]): int =
  for x in m:
    result += x.n.len + x.v.len + 32

proc `$`(m: seq[ModelEntry]): string =
  for x in m:
    result.add x.n & ": " & x.v & "\r\n"

block:
  echo "Test DynHeaders against a model"
  for round in 0 ..< 200:
    var size = rng.rand(600)
    var dh = initDynHeaders(size)
    var m = newSeq[ModelEntry]()  # newest first
    let indexed = round mod 2 == 0
    for _ in 0 ..< 500:
      case rng.rand(9)
      of 0:
        size = rng.rand(600)
        dh.setSize(size)
        while m.modelSize > size:
          discard m.pop()
      else:
        let n = randStr(8, "abc")
        let v = randStr(40, "xy")
        if rng.rand(1) == 0:
          dh.add(n, v)
        else:
          let line = n & ": " & v & "\r\n"
          dh.addLine(line, n.len)
        if n.len + v.len + 32 > size:
          m.setLen 0
        else:
          m.insert((n, v), 0)
          while m.modelSize > size:
            discard m.pop()
      doAssert dh.len == m.len
      doAssert $dh == $m
      if indexed:
        let n = randStr(8, "abc")
        let v = randStr(40, "xy")
        let nHash = strhash(n)
        var exact, name = -1
        for i in countdown(m.high, 0):
          if m[i].n == n:
            name = i
            if m[i].v == v:
              exact = i
        doAssert dh.find(n, v, pairhash(nHash, v)) == exact
        doAssert dh.findName(n, nHash) == name

block:
  echo "Test decode random bytes"
  var ok = 0
  for _ in 0 ..< 200_000:
    var s = newSeq[byte](1 + rng.rand(12))
    for b in mitems s:
      b = rng.rand(255).byte
    var dh = initDynHeaders(256)
    dh.add("foo", "bar")
    var ss = ""
    var bb = newSeq[HBounds]()
    try:
      hdecodeAll(s, dh, ss, bb)
      inc ok
    except DecodeError:
      discard
  doAssert ok > 1000

block:
  echo "Test encode/decode roundtrip"
  for _ in 0 ..< 500:
    var dhEnc = initDynHeaders(4096)
    var dhDec = initDynHeaders(4096)
    for _ in 0 ..< 20:
      var s = newSeq[byte]()
      var expected = ""
      for _ in 0 ..< rng.rand(10):
        let n = case rng.rand(3)
          of 0: ":path"
          of 1: "content-type"
          else: randStr(10, "abcd-")
        let v = randStr(30)
        let store = [stoYes, stoNo, stoNever][rng.rand(2)]
        hencode(n, v, dhEnc, s, store, huffman = rng.rand(1) == 0)
        expected.add n & ": " & v & "\r\n"
      var ss = ""
      var bb = newSeq[HBounds]()
      hdecodeAll(s, dhDec, ss, bb)
      doAssert ss == expected
      doAssert dhEnc == dhDec
      for b in bb:
        doAssert ss[b.n.b+1] == ':'
        doAssert ss[b.v.b+1] == '\r'

echo "ok"
