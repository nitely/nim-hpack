{.push raises: [].}

{.push checks: off.}
func strcopy*(
  x: var openArray[byte],
  y: openArray[byte],
  xi, yi, xyLen: int
) {.inline.} =
  assert x.len >= xi+xyLen
  assert y.len >= yi+xyLen
  for i in 0 ..< xyLen:
    x[xi+i] = y[yi+i]
{.pop.}

{.push checks: off.}
func strcmp*(
  x, y: openArray[byte],
  xi, yi, xyLen: int
): bool {.inline.} =
  assert x.len >= xi+xyLen
  assert y.len >= yi+xyLen
  var diff = 0'u8
  for i in 0 ..< xyLen:
    diff = diff or (x[xi+i] xor y[yi+i])
  diff == 0
{.pop.}

{.push checks: off.}
func strcmp*(
  x, y: openArray[byte]
): bool {.inline.} =
  if x.len != y.len:
    return false
  var diff = 0'u8
  for i in 0 ..< x.len:
    diff = diff or (x[i] xor y[i])
  diff == 0
{.pop.}

template setLenUninit2*(s, newlen: untyped): untyped =
  when (NimMajor, NimMinor, NimPatch) >= (2, 2, 10):
    setLenUninit(s, newlen)
  else:
    setLen(s, newlen)

template asBytes*(s: openArray[char]): untyped =
  s.toOpenArrayByte(0, s.high)

func toString*(s: openArray[byte]): string =
  result = newString(s.len)
  for i in 0 ..< s.len:
    result[i] = s[i].char
