# HPACK

An implementation of HPACK (Header Compression for HTTP/2).
Based on [rfc7541](https://tools.ietf.org/html/rfc7541).

> WIP!

## Compatibility

> nim >= 0.19 (devel)

## Usage

```nim
import hpack

proc toBytes(s: seq[uint16]): seq[byte] =
  result = newSeqOfCap[byte](s.len * 2)
  for b in s:
    result.add(byte(b shr 8))
    result.add(byte(b and 0xff))

# First request
let req1 = @[
  0x8286'u16, 0x8441, 0x0f77, 0x7777,
  0x2e65, 0x7861, 0x6d70, 0x6c65,
  0x2e63, 0x6f6d].toBytes
var ds = initDecodedStr()
var dh = initDynHeaders(256, 16)
assert hdecodeAll(req1, dh, ds) == req1.len
assert($ds ==
  ":method: GET\r\L" &
  ":scheme: http\r\L" &
  ":path: /\r\L" &
  ":authority: www.example.com\r\L")

# Second request
let req2 = @[
  0x8286'u16, 0x84be, 0x5808, 0x6e6f,
  0x2d63, 0x6163, 0x6865].toBytes
ds.reset()
assert hdecodeAll(req2, dh, ds) == req2.len
assert($ds ==
  ":method: GET\r\L" &
  ":scheme: http\r\L" &
  ":path: /\r\L" &
  ":authority: www.example.com\r\L" &
  "cache-control: no-cache\r\L")

# So on...
```

## Tests

```
nimble test
```

## LICENSE

MIT
