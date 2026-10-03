## Hash index

type
  Slot = object
    key: uint32
      ## 0 is empty
    id: uint32
  HashIndex* = object
    ## Maps a key to an id. Open addressing with
    ## linear probing; the load is kept <= 25%.
    ## Key 0 is reserved for empty slots
    slots: seq[Slot]
      ## its len is 0 or a power of 2
    count: int

func len*(x: HashIndex): int {.inline, raises: [].} =
  x.count

func clear*(x: var HashIndex) {.raises: [].} =
  for slot in mitems x.slots:
    slot = Slot()
  x.count = 0

{.push checks: off.}
func probe(x: HashIndex, key: uint32): int {.inline, raises: [].} =
  ## Return the slot of ``key``, or the empty
  ## slot where it would go
  let mask = x.slots.len-1
  result = key.int and mask
  while x.slots[result].key != 0 and x.slots[result].key != key:
    result = (result+1) and mask

func find*(x: HashIndex, key: uint32): int {.inline, raises: [].} =
  ## Return the id of ``key``, or -1
  assert key != 0
  if x.slots.len == 0:
    return -1
  let slot = x.slots[x.probe(key)]
  if slot.key == 0: -1 else: slot.id.int

func grow(x: var HashIndex) {.raises: [].} =
  let old = move x.slots
  x.slots = newSeq[Slot](max(64, old.len*2))
  for slot in old:
    if slot.key != 0:
      x.slots[x.probe(slot.key)] = slot

func put*(x: var HashIndex, key, id: uint32) {.raises: [].} =
  ## Map ``key`` to ``id``
  assert key != 0
  if (x.count+1)*4 > x.slots.len:
    x.grow()
  let i = x.probe(key)
  if x.slots[i].key == 0:
    inc x.count
  x.slots[i] = Slot(key: key, id: id)

func del*(x: var HashIndex, key, id: uint32) {.raises: [].} =
  ## Remove ``key`` if it maps to ``id``.
  ## Backward-shift delete, so there are no tombstones
  assert key != 0
  if x.slots.len == 0:
    return
  let mask = x.slots.len-1
  var i = x.probe(key)
  if x.slots[i] != Slot(key: key, id: id):
    return
  var j = i
  while true:
    j = (j+1) and mask
    if x.slots[j].key == 0:
      break
    let home = x.slots[j].key.int and mask
    if ((j-home) and mask) >= ((j-i) and mask):
      x.slots[i] = x.slots[j]
      i = j
  x.slots[i] = Slot()
  dec x.count
{.pop.}

when isMainModule:
  block:
    echo "Test HashIndex"
    var x = HashIndex()
    doAssert x.find(1) == -1
    x.put(1, 10)
    x.put(2, 20)
    doAssert x.len == 2
    doAssert x.find(1) == 10
    doAssert x.find(2) == 20
    doAssert x.find(3) == -1
    x.put(1, 11)
    doAssert x.len == 2
    doAssert x.find(1) == 11
    x.del(1, 10)  # maps to 11, so it stays
    doAssert x.find(1) == 11
    x.del(1, 11)
    doAssert x.find(1) == -1
    doAssert x.len == 1
    x.clear()
    doAssert x.len == 0
    doAssert x.find(2) == -1
  block:
    echo "Test HashIndex collisions"
    var x = HashIndex()
    # same home slot in a 64 slot table
    x.put(1, 1)
    x.put(65, 2)
    x.put(129, 3)
    x.put(2, 4)  # its home slot is taken by 65
    x.del(1, 1)
    doAssert x.find(1) == -1
    doAssert x.find(65) == 2
    doAssert x.find(129) == 3
    doAssert x.find(2) == 4
    x.del(65, 2)
    doAssert x.find(129) == 3
    doAssert x.find(2) == 4
  block:
    echo "Test HashIndex grow"
    var x = HashIndex()
    for k in 1'u32 .. 1000:
      x.put(k*7919, k)
    doAssert x.len == 1000
    for k in 1'u32 .. 1000:
      doAssert x.find(k*7919) == k.int
    for k in 1'u32 .. 500:
      x.del(k*7919, k)
    for k in 1'u32 .. 1000:
      doAssert x.find(k*7919) == (if k <= 500: -1 else: k.int)
