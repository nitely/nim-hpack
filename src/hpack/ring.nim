## Ring buffer queue

type Ring*[T] = object
  ## A queue that adds at the front and
  ## removes at the back. Index 0 is the front.
  ## It grows as needed, and never shrinks
  s: seq[T]
    ## its len is 0 or a power of 2
  head, count: int

func len*[T](r: Ring[T]): int {.inline, raises: [].} =
  r.count

func clear*[T](r: var Ring[T]) {.inline, raises: [].} =
  r.head = 0
  r.count = 0

{.push checks: off.}
func `[]`*[T](r: Ring[T], i: Natural): T {.inline, raises: [].} =
  assert i < r.count
  r.s[(r.head+i) and (r.s.len-1)]
{.pop.}

func grow[T](r: var Ring[T]) {.raises: [].} =
  var s = newSeq[T](max(16, r.s.len*2))
  for i in 0 ..< r.count:
    s[i] = r[i]
  r.s = move s
  r.head = 0

func addFirst*[T](r: var Ring[T], x: T) {.inline, raises: [].} =
  if r.count == r.s.len:
    r.grow()
  r.head = (r.head-1) and (r.s.len-1)
  r.s[r.head] = x
  inc r.count

func popLast*[T](r: var Ring[T]): T {.inline, raises: [].} =
  doAssert r.count > 0, "empty ring"
  result = r[r.count-1]
  dec r.count

when isMainModule:
  block:
    echo "Test Ring"
    var r = Ring[int]()
    doAssert r.len == 0
    r.addFirst(1)
    r.addFirst(2)
    doAssert r.len == 2
    doAssert r[0] == 2
    doAssert r[1] == 1
    doAssert r.popLast() == 1
    doAssert r.len == 1
    doAssert r[0] == 2
    r.clear()
    doAssert r.len == 0
  block:
    echo "Test Ring wrap around and grow"
    var r = Ring[int]()
    for i in 0 ..< 10:
      r.addFirst(i)
    for i in 0 ..< 5:
      doAssert r.popLast() == i
    # wraps around, then grows from 16 to 64
    for i in 10 ..< 50:
      r.addFirst(i)
    doAssert r.len == 45
    for i in 0 ..< 45:
      doAssert r[i] == 49-i
    for i in 5 ..< 50:
      doAssert r.popLast() == i
    doAssert r.len == 0
