## Internal byte and string helpers

when defined(gcc) or defined(clang) or defined(llvm_gcc):
  func bswap64(x: uint64): uint64 {.importc: "__builtin_bswap64", nodecl.}
else:
  func bswap64(x: uint64): uint64 {.inline.} =
    result = 0
    for i in 0 .. 7:
      result = result or (((x shr (i*8)) and 0xff) shl (56 - i*8))

template load64BE*(s: openArray[byte], i: int): uint64 =
  ## Load 8 bytes at ``s[i]`` as a big-endian integer
  var x {.noinit.}: uint64
  copyMem(addr x, unsafeAddr s[i], 8)
  when cpuEndian == littleEndian:
    bswap64(x)
  else:
    x

template store64BE*(s: var openArray[byte], i: int, x: uint64) =
  ## Store ``x`` at ``s[i]`` as 8 big-endian bytes
  var y {.noinit.} = when cpuEndian == littleEndian: bswap64(x) else: x
  copyMem(addr s[i], addr y, 8)

func eqStr*(a, b: openArray[char]): bool {.inline.} =
  a.len == b.len and (a.len == 0 or equalMem(unsafeAddr a[0], unsafeAddr b[0], a.len))

template loadLE(s: openArray[char], i, n: int): uint64 =
  ## Load ``n`` bytes at ``s[i]`` as a little-endian integer
  var x = 0'u64
  when nimvm:
    for k in 0 ..< n:
      x = x or (s[i+k].uint64 shl (8*k))
  else:
    when cpuEndian == littleEndian:
      copyMem(addr x, unsafeAddr s[i], n)
    else:
      for k in 0 ..< n:
        x = x or (s[i+k].uint64 shl (8*k))
  x

func mix(h, x: uint64): uint64 {.inline.} =
  result = (h xor x) * 0x9E3779B97F4A7C15'u64
  result = result xor (result shr 29)

{.push checks: off.}

func strhash*(s: openArray[char]): uint32 =
  ## Hash for header names. It gives the same
  ## result at compile time and at run time, so static
  ## tables can be built as constants.
  ## The tail is read with overlapping loads, so
  ## there are no per byte loops
  var h = s.len.uint64 * 0x9E3779B97F4A7C15'u64
  var i = 0
  while i + 8 < s.len:
    h = mix(h, loadLE(s, i, 8))
    inc i, 8
  let n = s.len-i
  if n >= 4:
    h = mix(h, loadLE(s, i, 4) or (loadLE(s, s.len-4, 4) shl 32))
  elif n > 0:
    h = mix(h,
      s[i].uint64 or
      (s[i + (n shr 1)].uint64 shl 8) or
      (s[s.len-1].uint64 shl 16)
    )
  h = h xor (h shr 32)
  result = uint32(h and 0xffff_ffff'u64)

func pairhash*(nHash: uint32, v: openArray[char]): uint32 =
  ## Hash of a name and value;
  ## ``nHash`` is the ``strhash`` of the name
  let h = mix(nHash.uint64 shl 32 or strhash(v).uint64, 0)
  result = uint32((h xor (h shr 32)) and 0xffff_ffff'u64)

{.pop.}
