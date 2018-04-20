
type
  Queue = object
    data: seq[int]
    head: int
    tail: int
    pos: int

proc initQueue(size: int): Queue =
  Queue(
    data: newSeq[int](size),
    head: size-1,
    tail: 0,
    pos: 0)

proc enqueue(q: var Queue, x: int) =
  q.head = (q.head+1) mod q.data.len
  q.data[q.head] = x
  inc q.pos

proc dequeue(q: var Queue): int =
  result = q.data[q.tail]
  q.tail = (q.tail+1) mod q.data.len
  dec q.pos

var x = initQueue(2)
x.enqueue(1)
echo x.dequeue()
x.enqueue(5)
echo x.dequeue()
x.enqueue(1)
x.enqueue(5)
echo x.data
x.enqueue(10)
echo x.data

type
  StrQueue = object
    datastr: string
    data: seq[Slice[int]]
    head: int
    tail: int
    pos: int

proc initStrQueue(size: int): StrQueue =
  Queue(
    datastr: newString(200),
    data: newSeq[Slice[int]](size),
    head: size-1,
    tail: 0,
    pos: 0)

proc enqueue(q: var StrQueue, x: string) =
  let y = q[q.head]
  q.head = (q.head+1) mod q.data.len
  q.data[q.head] = Slice(a: y.b, y.b+x.len)
  inc q.pos
  for c in x:
    q.head = (q.head+1) mod q.data.len
    q.data[q.head] = x
    inc q.pos

proc dequeue(q: var StrQueue): int =
  result = q.data[q.tail]
  q.tail = (q.tail+1) mod q.data.len
  dec q.pos
