# HPACK

An implementation of HPACK (Header Compression for HTTP/2).
Based on [rfc7541](https://tools.ietf.org/html/rfc7541).

This lib is used by https://github.com/nitely/nim-hyperx

## Compatibility

> Nim +2

## Install

```
nimble install hpack
```

## Docs

[nitely.github.io/nim-hpack](https://nitely.github.io/nim-hpack/)

## Usage

### Decode

```nim
import hpack

proc toBytes(s: seq[uint16]): seq[byte] =
  result = newSeqOfCap[byte](s.len * 2)
  for b in s:
    result.add(byte(b shr 8))
    result.add(byte(b and 0xff))

# First request
let req1 = @[
  0x8286'u16, 0x8441, 0x8cf1, 0xe3c2,
  0xe5f2, 0x3a6b, 0xa0ab, 0x90f4].toBytes
var ds = initDecodedStr()
var dh = initDynHeaders(256)
assert hdecodeAll(req1, dh, ds) == req1.len
assert($ds ==
  ":method: GET\r\L" &
  ":scheme: http\r\L" &
  ":path: /\r\L" &
  ":authority: www.example.com\r\L")

# Second request
let req2 = @[
  0x8286'u16, 0x84be, 0x5886,
  0xa8eb, 0x1064, 0x9cbf].toBytes
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

### Encode

```nim
import hpack

proc toBytes(s: seq[uint16]): seq[byte] =
  result = newSeqOfCap[byte](s.len * 2)
  for b in s:
    result.add(byte(b shr 8))
    result.add(byte(b and 0xff))

# First response
var resp = newSeq[byte]()
var dh = initDynHeaders(256)
hencode(":method", "GET", dh, resp)
hencode(":scheme", "http", dh, resp)
hencode(":path", "/", dh, resp)
hencode(":authority", "www.example.com", dh, resp)
assert resp == @[
  0x8286'u16, 0x8441, 0x8cf1, 0xe3c2,
  0xe5f2, 0x3a6b, 0xa0ab, 0x90f4].toBytes

# Second response
resp.setLen(0)
hencode(":method", "GET", dh, resp)
hencode(":scheme", "http", dh, resp)
hencode(":path", "/", dh, resp)
hencode(":authority", "www.example.com", dh, resp)
hencode("cache-control", "no-cache", dh, resp)
assert resp == @[
  0x8286'u16, 0x84be, 0x5886,
  0xa8eb, 0x1064, 0x9cbf].toBytes

# So on...
```

## Tests

```
nimble test
```

## LICENSE

MIT
