type
  StrQueue = object
    s: string
    pos: int  # todo: use b[head].b
    filled: int
    b: seq[Slice[int]]
    head: int
    tail: int
    i: int  # todo: remove

proc initStrQueue(): StrQueue =
  var size = 10
  StrQueue(
    s: newString(40),
    pos: 0,
    filled: 0,
    b: newSeq[Slice[int]](size),
    head: size-1,
    tail: 0,
    i: 0)

proc len(q: StrQueue): int =
  q.i

proc left(q: StrQueue): int =
  ## Return available space
  q.s.len-q.filled

proc pop(q: var StrQueue): Slice[int] =
  assert q.i > 0
  result = q.b[q.tail]
  q.tail = (q.tail+1) mod q.b.len
  dec q.i
  q.pos = result.a
  dec(q.filled, result.b-result.a)
  assert q.filled >= 0

proc add(q: var StrQueue, x: string) =
  while q.len > 0 and x.len > q.left:
    discard q.pop()
  if x.len > q.s.len:
    raise newException(ValueError, "string to long")
  q.head = (q.head+1) mod q.b.len
  q.b[q.head] = q.pos .. q.pos+x.len-1
  q.i = min(q.b.len, q.i+1)
  for c in x:
    q.s[q.pos] = c
    q.pos = (q.pos+1) mod q.s.len
  inc(q.filled, x.len)
  assert q.filled <= q.s.len

iterator items(q: StrQueue): Slice[int] =
  var i = 0
  while i < q.i:
    yield q.b[(q.tail+i) mod q.b.len]
    inc i

proc substr(q: StrQueue, s: var string, b: Slice[int]) =
  let o = s.len
  s.setLen(s.len+b.b-b.a+1)
  for i in b:
    s[o+i-b.a] = q.s[i mod q.s.len]

var x = initStrQueue()
x.add("hello")
x.add("world")
echo x.s[x.pop()]
echo x.s[x.pop()]
x.add("helloA")
x.add("helloB")
x.add("helloC")
#for y in x:
#  echo x.s[y]
x.add("helloD")
x.add("helloE")
x.add("helloF")
x.add("helloG")
var s = ""
for b in x:
  s.setLen(0)
  x.substr(s, b)
  echo s
