# Package

version = "0.1.1"
author = "Esteban Castro Borsani (@nitely)"
description = "HPACK (Header Compression for HTTP/2)"
license = "MIT"
srcDir = "src"
skipDirs = @["tests"]

requires "nim >= 0.18.1"

task gen, "Gen data":
  exec "nim c -r gen/huffman.nim"

task test, "Test":
  exec "nim c -r src/hpack/hcollections.nim"
  exec "nim c -r src/hpack/encoder.nim"
  exec "nim c -r src/hpack/huffman_encoder.nim"
  exec "nim c -r src/hpack/decoder.nim"
  exec "nim c -r src/hpack/huffman_decoder.nim"
  exec "nim c -r tests/tests.nim"

task docs, "Docs":
  exec "nim doc2 -o:./docs --project ./src/hpack.nim"
  exec "mv ./docs/hpack.html ./docs/index.html"
  exec "rm -fr ./docs/*/*_data.html"
