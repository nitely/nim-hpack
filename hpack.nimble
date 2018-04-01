# Package

version = "0.1.0"
author = "Esteban Castro Borsani (@nitely)"
description = "HPACK (Header Compression for HTTP/2)"
license = "MIT"
srcDir = "src"
skipDirs = @["tests"]

requires "nim >= 0.18.0"

task gen, "Gen data":
  exec "nim c -r gen/huffman.nim"

task test, "Test":
  exec "nim c -r src/hpack/huffman_decoder.nim"

task docs, "Docs":
  exec "nim doc2 -o:./docs/index.html ./src/hpack.nim"
