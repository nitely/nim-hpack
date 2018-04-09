import unittest

import hpack

proc toBytes(s: seq[uint16]): seq[byte] =
  result = newSeqOfCap[byte](len(s) * 2)
  for b in s:
    if b shr 8 > 0'u16:
      result.add(byte(b shr 8))
    result.add(byte(b and 0xff))

test "Test HC decode example.com":
  # from https://tools.ietf.org/html/rfc7541#appendix-C.4.1
  let msg = @[
    0xf1e3'u16, 0xc2e5, 0xf23a,
    0x6ba0, 0xab90, 0xf4ff].toBytes
  var d = ""
  check hcdecode(msg, d) != -1
  check d == "www.example.com"

test "Test HC decode no-cache":
  # from https://tools.ietf.org/html/rfc7541#appendix-C.4.2
  let msg = @[0xa8eb'u16, 0x1064, 0x9cbf].toBytes
  var d = ""
  check hcdecode(msg, d) != -1
  check d == "no-cache"

test "Test HC decode custom":
  # from https://tools.ietf.org/html/rfc7541#appendix-C.4.3
  block:
    let msg = @[0x25a8'u16, 0x49e9, 0x5ba9, 0x7d7f].toBytes
    var d = ""
    check hcdecode(msg, d) != -1
    check d == "custom-key"
  block:
    let msg = @[0x25a8'u16, 0x49e9, 0x5bb8, 0xe8b4, 0xbf].toBytes
    var d = ""
    check hcdecode(msg, d) != -1
    check d == "custom-value"

test "Should fail when has EOS":
  let msg = @[0xffff'u16, 0xffff].toBytes
  var d = ""
  check hcdecode(msg, d) == -1
