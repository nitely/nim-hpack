# Package

version = "0.5.0"
author = "Esteban C Borsani (@nitely)"
description = "HPACK (Header Compression for HTTP/2)"
license = "MIT"
srcDir = "src"
skipDirs = @["tests", "gen", "bench"]

requires "nim >= 2.0.14"

task gen, "Gen data":
  exec "nim c -r gen/huffman.nim"

task test, "Test":
  exec "nim c -r -o:bin/hpack src/hpack.nim"
  exec "nim c -r src/hpack/ring.nim"
  exec "nim c -r src/hpack/hcollections.nim"
  exec "nim c -r src/hpack/encoder.nim"
  exec "nim c -r src/hpack/huffman_encoder.nim"
  exec "nim c -r src/hpack/decoder.nim"
  exec "nim c -r src/hpack/huffman_decoder.nim"
  exec "nim c -r tests/tests.nim"
  exec "nim c -r tests/testdata2.nim"
  exec "nim c -r tests/testreadme.nim"

task bench, "Benchmark":
  exec "nim c -r -d:release -o:bin/bench bench/bench.nim"

task docs, "Docs":
  exec "nim doc2 -o:./docs --project ./src/hpack.nim"
  exec "mv ./docs/hpack.html ./docs/index.html"
  exec "rm -fr ./docs/*/*_data.html"
