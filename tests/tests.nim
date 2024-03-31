import std/unittest

import ../src/hpack/huffman_decoder
import ../src/hpack

proc toBytes(s: seq[uint16]): seq[byte] =
  result = newSeqOfCap[byte](len(s) * 2)
  for b in s:
    result.add(byte(b shr 8))
    result.add(byte(b and 0xff))

suite "Test Huffman decoder":
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
      var msg = @[0x25a8'u16, 0x49e9, 0x5bb8, 0xe8b4].toBytes
      msg.add(byte 0xbf'u8)
      var d = ""
      check hcdecode(msg, d) != -1
      check d == "custom-value"

  test "Should fail when has EOS":
    let msg = @[0xffff'u16, 0xffff].toBytes
    var d = ""
    check hcdecode(msg, d) == -1

suite "Decoder - Test Header Field Representation Examples":
  test "Test Literal Header Field with Indexing":
    var
      ic = @[
        0x400a'u16, 0x6375, 0x7374, 0x6f6d,
        0x2d6b, 0x6579, 0x0d63, 0x7573,
        0x746f, 0x6d2d, 0x6865, 0x6164, 0x6572].toBytes
      d = initDecodedStr()
      dh = initDynHeaders(256)
    check hdecode(ic, dh, d) == ic.len
    var i = 0
    for h in d:
      check d.s[h.n] == "custom-key"
      check d.s[h.v] == "custom-header"
      inc i
    check i == 1
    check dh.len == 1
    check $dh == "custom-key: custom-header\r\L"

  test "Test Literal Header Field without Indexing":
    var
      ic = @[
        0x040c'u16, 0x2f73, 0x616d,
        0x706c, 0x652f, 0x7061, 0x7468].toBytes
      d = initDecodedStr()
      dh = initDynHeaders(256)
    check hdecode(ic, dh, d) == ic.len
    var i = 0
    for h in d:
      check d.s[h.n] == ":path"
      check d.s[h.v] == "/sample/path"
      inc i
    check i == 1
    check dh.len == 0

  test "Test Literal Header Field Never Indexed":
    var ic = @[
      0x1008'u16, 0x7061, 0x7373, 0x776f,
      0x7264, 0x0673, 0x6563, 0x7265].toBytes
    ic.add(byte 0x74'u8)
    var
      d = initDecodedStr()
      dh = initDynHeaders(256)
    check hdecode(ic, dh, d) == ic.len
    var i = 0
    for h in d:
      check d.s[h.n] == "password"
      check d.s[h.v] == "secret"
      inc i
    check i == 1
    check dh.len == 0

  test "Test Indexed Header Field":
    var
      ic = @[byte 0x82'u8]
      d = initDecodedStr()
      dh = initDynHeaders(256)
    check hdecode(ic, dh, d) == ic.len
    var i = 0
    for h in d:
      check d.s[h.n] == ":method"
      check d.s[h.v] == "GET"
      inc i
    check i == 1
    check dh.len == 0

suite "Decoder - Request Examples without Huffman Coding":
  var dh = initDynHeaders(256)

  test "First Request":
    var
      ic = @[
        0x8286'u16, 0x8441, 0x0f77, 0x7777,
        0x2e65, 0x7861, 0x6d70, 0x6c65,
        0x2e63, 0x6f6d].toBytes
      d = initDecodedStr()
      expected = [
        [":method", "GET"],
        [":scheme", "http"],
        [":path", "/"],
        [":authority", "www.example.com"]]
    hdecodeAll(ic, dh, d)
    var i = 0
    for h in d:
      check d.s[h.n] == expected[i][0]
      check d.s[h.v] == expected[i][1]
      inc i
    check i == expected.len
    check dh.len == 1
    check $dh == ":authority: www.example.com\r\L"

  test "Second Request":
    var
      ic = @[
        0x8286'u16, 0x84be, 0x5808, 0x6e6f,
        0x2d63, 0x6163, 0x6865].toBytes
      d = initDecodedStr()
      expected = [
        [":method", "GET"],
        [":scheme", "http"],
        [":path", "/"],
        [":authority", "www.example.com"],
        ["cache-control", "no-cache"]]
    hdecodeAll(ic, dh, d)
    var i = 0
    for h in d:
      check d.s[h.n] == expected[i][0]
      check d.s[h.v] == expected[i][1]
      inc i
    check i == expected.len
    check dh.len == 2
    check $dh ==
      "cache-control: no-cache\r\L" &
      ":authority: www.example.com\r\L"

  test "Third Request":
    var ic = @[
      0x8287'u16, 0x85bf, 0x400a, 0x6375,
      0x7374, 0x6f6d, 0x2d6b, 0x6579,
      0x0c63, 0x7573, 0x746f, 0x6d2d,
      0x7661, 0x6c75].toBytes
    ic.add(byte 0x65'u16)
    var
      d = initDecodedStr()
      expected = [
        [":method", "GET"],
        [":scheme", "https"],
        [":path", "/index.html"],
        [":authority", "www.example.com"],
        ["custom-key", "custom-value"]]
    hdecodeAll(ic, dh, d)
    var i = 0
    for h in d:
      check d.s[h.n] == expected[i][0]
      check d.s[h.v] == expected[i][1]
      inc i
    check i == expected.len
    check dh.len == 3
    check $dh ==
      "custom-key: custom-value\r\L" &
      "cache-control: no-cache\r\L" &
      ":authority: www.example.com\r\L"

suite "Decoder - Request Examples with Huffman Coding":
  var dh = initDynHeaders(256)

  test "First Request":
    var ic = @[
      0x8286'u16, 0x8441, 0x8cf1, 0xe3c2,
      0xe5f2, 0x3a6b, 0xa0ab, 0x90f4].toBytes
    ic.add(byte 0xff'u16)
    var
      d = initDecodedStr()
      expected = [
        [":method", "GET"],
        [":scheme", "http"],
        [":path", "/"],
        [":authority", "www.example.com"]]
    hdecodeAll(ic, dh, d)
    var i = 0
    for h in d:
      check d.s[h.n] == expected[i][0]
      check d.s[h.v] == expected[i][1]
      inc i
    check i == expected.len
    check dh.len == 1
    check $dh == ":authority: www.example.com\r\L"

  test "Second Request":
    var
      ic = @[
        0x8286'u16, 0x84be, 0x5886,
        0xa8eb, 0x1064, 0x9cbf].toBytes
      d = initDecodedStr()
      expected = [
        [":method", "GET"],
        [":scheme", "http"],
        [":path", "/"],
        [":authority", "www.example.com"],
        ["cache-control", "no-cache"]]
    hdecodeAll(ic, dh, d)
    var i = 0
    for h in d:
      check d.s[h.n] == expected[i][0]
      check d.s[h.v] == expected[i][1]
      inc i
    check i == expected.len
    check dh.len == 2
    check $dh ==
      "cache-control: no-cache\r\L" &
      ":authority: www.example.com\r\L"

  test "Third Request":
    var
      ic = @[
        0x8287'u16, 0x85bf, 0x4088, 0x25a8,
        0x49e9, 0x5ba9, 0x7d7f, 0x8925,
        0xa849, 0xe95b, 0xb8e8, 0xb4bf].toBytes
      d = initDecodedStr()
      expected = [
        [":method", "GET"],
        [":scheme", "https"],
        [":path", "/index.html"],
        [":authority", "www.example.com"],
        ["custom-key", "custom-value"]]
    hdecodeAll(ic, dh, d)
    var i = 0
    for h in d:
      check d.s[h.n] == expected[i][0]
      check d.s[h.v] == expected[i][1]
      inc i
    check i == expected.len
    check dh.len == 3
    check $dh ==
      "custom-key: custom-value\r\L" &
      "cache-control: no-cache\r\L" &
      ":authority: www.example.com\r\L"

suite "Decoder - Response Examples without Huffman Coding":
  var dh = initDynHeaders(256)

  test "First Response":
    var
      ic = @[
        0x4803'u16, 0x3330, 0x3258, 0x0770,
        0x7269, 0x7661, 0x7465, 0x611d,
        0x4d6f, 0x6e2c, 0x2032, 0x3120,
        0x4f63, 0x7420, 0x3230, 0x3133,
        0x2032, 0x303a, 0x3133, 0x3a32,
        0x3120, 0x474d, 0x546e, 0x1768,
        0x7474, 0x7073, 0x3a2f, 0x2f77,
        0x7777, 0x2e65, 0x7861, 0x6d70,
        0x6c65, 0x2e63, 0x6f6d].toBytes
      d = initDecodedStr()
      expected = [
        [":status", "302"],
        ["cache-control", "private"],
        ["date", "Mon, 21 Oct 2013 20:13:21 GMT"],
        ["location", "https://www.example.com"]]
    hdecodeAll(ic, dh, d)
    var i = 0
    for h in d:
      check d.s[h.n] == expected[i][0]
      check d.s[h.v] == expected[i][1]
      inc i
    check i == expected.len
    check dh.len == 4
    check $dh ==
      "location: https://www.example.com\r\L" &
      "date: Mon, 21 Oct 2013 20:13:21 GMT\r\L" &
      "cache-control: private\r\L" &
      ":status: 302\r\L"

  test "Second Response":
    var
      ic = @[
        0x4803'u16, 0x3330, 0x37c1, 0xc0bf].toBytes
      d = initDecodedStr()
      expected = [
        [":status", "307"],
        ["cache-control", "private"],
        ["date", "Mon, 21 Oct 2013 20:13:21 GMT"],
        ["location", "https://www.example.com"]]
    hdecodeAll(ic, dh, d)
    var i = 0
    for h in d:
      check d.s[h.n] == expected[i][0]
      check d.s[h.v] == expected[i][1]
      inc i
    check i == expected.len
    check dh.len == 4
    check $dh ==
      ":status: 307\r\L" &
      "location: https://www.example.com\r\L" &
      "date: Mon, 21 Oct 2013 20:13:21 GMT\r\L" &
      "cache-control: private\r\L"

  test "Third Response":
    var
      ic = @[
        0x88c1'u16, 0x611d, 0x4d6f, 0x6e2c,
        0x2032, 0x3120, 0x4f63, 0x7420,
        0x3230, 0x3133, 0x2032, 0x303a,
        0x3133, 0x3a32, 0x3220, 0x474d,
        0x54c0, 0x5a04, 0x677a, 0x6970,
        0x7738, 0x666f, 0x6f3d, 0x4153,
        0x444a, 0x4b48, 0x514b, 0x425a,
        0x584f, 0x5157, 0x454f, 0x5049,
        0x5541, 0x5851, 0x5745, 0x4f49,
        0x553b, 0x206d, 0x6178, 0x2d61,
        0x6765, 0x3d33, 0x3630, 0x303b,
        0x2076, 0x6572, 0x7369, 0x6f6e,
        0x3d31].toBytes
      d = initDecodedStr()
      expected = [
        [":status", "200"],
        ["cache-control", "private"],
        ["date", "Mon, 21 Oct 2013 20:13:22 GMT"],
        ["location", "https://www.example.com"],
        ["content-encoding", "gzip"],
        ["set-cookie",
         "foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; max-age=3600; version=1"]]
    hdecodeAll(ic, dh, d)
    var i = 0
    for h in d:
      check d.s[h.n] == expected[i][0]
      check d.s[h.v] == expected[i][1]
      inc i
    check i == expected.len
    check dh.len == 3
    check $dh ==
      "set-cookie: foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; " &
      "max-age=3600; version=1\r\L" &
      "content-encoding: gzip\r\L" &
      "date: Mon, 21 Oct 2013 20:13:22 GMT\r\L"

suite "Decoder - Response Examples with Huffman Coding":
  var dh = initDynHeaders(256)

  test "First Response":
    var
      ic = @[
        0x4882'u16, 0x6402, 0x5885, 0xaec3,
        0x771a, 0x4b61, 0x96d0, 0x7abe,
        0x9410, 0x54d4, 0x44a8, 0x2005,
        0x9504, 0x0b81, 0x66e0, 0x82a6,
        0x2d1b, 0xff6e, 0x919d, 0x29ad,
        0x1718, 0x63c7, 0x8f0b, 0x97c8,
        0xe9ae, 0x82ae, 0x43d3].toBytes
      d = initDecodedStr()
      expected = [
        [":status", "302"],
        ["cache-control", "private"],
        ["date", "Mon, 21 Oct 2013 20:13:21 GMT"],
        ["location", "https://www.example.com"]]
    hdecodeAll(ic, dh, d)
    var i = 0
    for h in d:
      check d.s[h.n] == expected[i][0]
      check d.s[h.v] == expected[i][1]
      inc i
    check i == expected.len
    check dh.len == 4
    check $dh ==
      "location: https://www.example.com\r\L" &
      "date: Mon, 21 Oct 2013 20:13:21 GMT\r\L" &
      "cache-control: private\r\L" &
      ":status: 302\r\L"

  test "Second Response":
    var
      ic = @[
        0x4883'u16, 0x640e, 0xffc1, 0xc0bf].toBytes
      d = initDecodedStr()
      expected = [
        [":status", "307"],
        ["cache-control", "private"],
        ["date", "Mon, 21 Oct 2013 20:13:21 GMT"],
        ["location", "https://www.example.com"]]
    hdecodeAll(ic, dh, d)
    var i = 0
    for h in d:
      check d.s[h.n] == expected[i][0]
      check d.s[h.v] == expected[i][1]
      inc i
    check i == expected.len
    check dh.len == 4
    check $dh ==
      ":status: 307\r\L" &
      "location: https://www.example.com\r\L" &
      "date: Mon, 21 Oct 2013 20:13:21 GMT\r\L" &
      "cache-control: private\r\L"

  test "Third Response":
    var ic = @[
      0x88c1'u16, 0x6196, 0xd07a, 0xbe94,
      0x1054, 0xd444, 0xa820, 0x0595,
      0x040b, 0x8166, 0xe084, 0xa62d,
      0x1bff, 0xc05a, 0x839b, 0xd9ab,
      0x77ad, 0x94e7, 0x821d, 0xd7f2,
      0xe6c7, 0xb335, 0xdfdf, 0xcd5b,
      0x3960, 0xd5af, 0x2708, 0x7f36,
      0x72c1, 0xab27, 0x0fb5, 0x291f,
      0x9587, 0x3160, 0x65c0, 0x03ed,
      0x4ee5, 0xb106, 0x3d50].toBytes
    ic.add(byte 0x07'u8)
    var
      d = initDecodedStr()
      expected = [
        [":status", "200"],
        ["cache-control", "private"],
        ["date", "Mon, 21 Oct 2013 20:13:22 GMT"],
        ["location", "https://www.example.com"],
        ["content-encoding", "gzip"],
        ["set-cookie",
         "foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; max-age=3600; version=1"]]
    hdecodeAll(ic, dh, d)
    var i = 0
    for h in d:
      check d.s[h.n] == expected[i][0]
      check d.s[h.v] == expected[i][1]
      inc i
    check i == expected.len
    check dh.len == 3
    check $dh ==
      "set-cookie: foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; " &
      "max-age=3600; version=1\r\L" &
      "content-encoding: gzip\r\L" &
      "date: Mon, 21 Oct 2013 20:13:22 GMT\r\L"

suite "Encoder - Header Field Representation Examples":
  test "Literal Header Field with Indexing":
    var
      dh = initDynHeaders(256)
      ic = newSeq[byte]()
      expected = @[
        0x400a'u16, 0x6375, 0x7374, 0x6f6d,
        0x2d6b, 0x6579, 0x0d63, 0x7573,
        0x746f, 0x6d2d, 0x6865, 0x6164, 0x6572].toBytes
    check hencode(
      "custom-key", "custom-header", dh, ic, huffman = false) == expected.len
    check ic == expected
    check $dh == "custom-key: custom-header\r\L"

  test "Literal Header Field without Indexing":
    var
      dh = initDynHeaders(256)
      ic = newSeq[byte]()
      expected = @[
        0x040c'u16, 0x2f73, 0x616d,
        0x706c, 0x652f, 0x7061, 0x7468].toBytes
    doAssert hencode(
      ":path", "/sample/path", dh,
      ic, store = stoNo, huffman = false) == expected.len
    doAssert ic == expected
    doAssert dh.len == 0

  test "Literal Header Field Never Indexed":
    var
      dh = initDynHeaders(256)
      ic = newSeq[byte]()
      expected = @[
        0x1008'u16, 0x7061, 0x7373, 0x776f,
        0x7264, 0x0673, 0x6563, 0x7265].toBytes
    expected.add(byte 0x74'u8)
    doAssert hencode(
      "password", "secret", dh,
      ic, store = stoNever, huffman = false) == expected.len
    doAssert ic == expected
    doAssert dh.len == 0

  test "Indexed Header Field":
    var
      dh = initDynHeaders(256)
      ic = newSeq[byte]()
      expected = @[byte 0x82'u8]
    doAssert hencode(
      ":method", "GET", dh,
      ic, store = stoNo, huffman = false) == expected.len
    doAssert ic == expected
    doAssert dh.len == 0

suite "Encoder - Request Examples without Huffman Coding":
  var dh = initDynHeaders(256)

  test "First Request":
    var
      ic = newSeq[byte]()
      expected = @[
        0x8286'u16, 0x8441, 0x0f77, 0x7777,
        0x2e65, 0x7861, 0x6d70, 0x6c65,
        0x2e63, 0x6f6d].toBytes
      hs = [
        [":method", "GET"],
        [":scheme", "http"],
        [":path", "/"],
        [":authority", "www.example.com"]]
    for h in hs:
      hencode(
        h[0], h[1], dh, ic, huffman = false)
    check ic == expected
    check $dh == ":authority: www.example.com\r\L"

  test "Second Request":
    var
      ic = newSeq[byte]()
      expected = @[
        0x8286'u16, 0x84be, 0x5808, 0x6e6f,
        0x2d63, 0x6163, 0x6865].toBytes
      hs = [
        [":method", "GET"],
        [":scheme", "http"],
        [":path", "/"],
        [":authority", "www.example.com"],
        ["cache-control", "no-cache"]]
    for h in hs:
      hencode(
        h[0], h[1], dh, ic, huffman = false)
    check ic == expected
    check $dh ==
      "cache-control: no-cache\r\L" &
      ":authority: www.example.com\r\L"

  test "Third Request":
    var
      ic = newSeq[byte]()
      expected = @[
        0x8287'u16, 0x85bf, 0x400a, 0x6375,
        0x7374, 0x6f6d, 0x2d6b, 0x6579,
        0x0c63, 0x7573, 0x746f, 0x6d2d,
        0x7661, 0x6c75].toBytes
    expected.add(byte 0x65'u16)
    var
      hs = [
        [":method", "GET"],
        [":scheme", "https"],
        [":path", "/index.html"],
        [":authority", "www.example.com"],
        ["custom-key", "custom-value"]]
    for h in hs:
      hencode(
        h[0], h[1], dh, ic, huffman = false)
    check ic == expected
    check $dh ==
      "custom-key: custom-value\r\L" &
      "cache-control: no-cache\r\L" &
      ":authority: www.example.com\r\L"

suite "Encoder - Request Examples with Huffman Coding":
  var dh = initDynHeaders(256)

  test "First Request":
    var
      ic = newSeq[byte]()
      expected = @[
        0x8286'u16, 0x8441, 0x8cf1, 0xe3c2,
        0xe5f2, 0x3a6b, 0xa0ab, 0x90f4].toBytes
    expected.add(byte 0xff'u16)
    var
      hs = [
        [":method", "GET"],
        [":scheme", "http"],
        [":path", "/"],
        [":authority", "www.example.com"]]
    for h in hs:
      hencode(h[0], h[1], dh, ic)
    check ic == expected
    check $dh == ":authority: www.example.com\r\L"

  test "Second Request":
    var
      ic = newSeq[byte]()
      expected = @[
        0x8286'u16, 0x84be, 0x5886,
        0xa8eb, 0x1064, 0x9cbf].toBytes
      hs = [
        [":method", "GET"],
        [":scheme", "http"],
        [":path", "/"],
        [":authority", "www.example.com"],
        ["cache-control", "no-cache"]]
    for h in hs:
      hencode(h[0], h[1], dh, ic)
    check ic == expected
    check $dh ==
      "cache-control: no-cache\r\L" &
      ":authority: www.example.com\r\L"

  test "Third Request":
    var
      ic = newSeq[byte]()
      expected = @[
        0x8287'u16, 0x85bf, 0x4088, 0x25a8,
        0x49e9, 0x5ba9, 0x7d7f, 0x8925,
        0xa849, 0xe95b, 0xb8e8, 0xb4bf].toBytes
      hs = [
        [":method", "GET"],
        [":scheme", "https"],
        [":path", "/index.html"],
        [":authority", "www.example.com"],
        ["custom-key", "custom-value"]]
    for h in hs:
      hencode(h[0], h[1], dh, ic)
    check ic == expected
    check $dh ==
      "custom-key: custom-value\r\L" &
      "cache-control: no-cache\r\L" &
      ":authority: www.example.com\r\L"

suite "Encoder - Response Examples without Huffman Coding":
  var dh = initDynHeaders(256)

  test "First Response":
    var
      ic = newSeq[byte]()
      expected = @[
        0x4803'u16, 0x3330, 0x3258, 0x0770,
        0x7269, 0x7661, 0x7465, 0x611d,
        0x4d6f, 0x6e2c, 0x2032, 0x3120,
        0x4f63, 0x7420, 0x3230, 0x3133,
        0x2032, 0x303a, 0x3133, 0x3a32,
        0x3120, 0x474d, 0x546e, 0x1768,
        0x7474, 0x7073, 0x3a2f, 0x2f77,
        0x7777, 0x2e65, 0x7861, 0x6d70,
        0x6c65, 0x2e63, 0x6f6d].toBytes
      hs = [
        [":status", "302"],
        ["cache-control", "private"],
        ["date", "Mon, 21 Oct 2013 20:13:21 GMT"],
        ["location", "https://www.example.com"]]
    for h in hs:
      hencode(h[0], h[1], dh, ic, huffman = false)
    check ic == expected
    check $dh ==
      "location: https://www.example.com\r\L" &
      "date: Mon, 21 Oct 2013 20:13:21 GMT\r\L" &
      "cache-control: private\r\L" &
      ":status: 302\r\L"

  test "Second Response":
    var
      ic = newSeq[byte]()
      expected = @[
        0x4803'u16, 0x3330, 0x37c1, 0xc0bf].toBytes
      hs = [
        [":status", "307"],
        ["cache-control", "private"],
        ["date", "Mon, 21 Oct 2013 20:13:21 GMT"],
        ["location", "https://www.example.com"]]
    for h in hs:
      hencode(h[0], h[1], dh, ic, huffman = false)
    check ic == expected
    check $dh ==
      ":status: 307\r\L" &
      "location: https://www.example.com\r\L" &
      "date: Mon, 21 Oct 2013 20:13:21 GMT\r\L" &
      "cache-control: private\r\L"

  test "Third Response":
    var
      ic = newSeq[byte]()
      expected = @[
        0x88c1'u16, 0x611d, 0x4d6f, 0x6e2c,
        0x2032, 0x3120, 0x4f63, 0x7420,
        0x3230, 0x3133, 0x2032, 0x303a,
        0x3133, 0x3a32, 0x3220, 0x474d,
        0x54c0, 0x5a04, 0x677a, 0x6970,
        0x7738, 0x666f, 0x6f3d, 0x4153,
        0x444a, 0x4b48, 0x514b, 0x425a,
        0x584f, 0x5157, 0x454f, 0x5049,
        0x5541, 0x5851, 0x5745, 0x4f49,
        0x553b, 0x206d, 0x6178, 0x2d61,
        0x6765, 0x3d33, 0x3630, 0x303b,
        0x2076, 0x6572, 0x7369, 0x6f6e,
        0x3d31].toBytes
      hs = [
        [":status", "200"],
        ["cache-control", "private"],
        ["date", "Mon, 21 Oct 2013 20:13:22 GMT"],
        ["location", "https://www.example.com"],
        ["content-encoding", "gzip"],
        ["set-cookie",
         "foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; max-age=3600; version=1"]]
    for h in hs:
      hencode(h[0], h[1], dh, ic, huffman = false)
    check ic == expected
    check $dh ==
      "set-cookie: foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; " &
      "max-age=3600; version=1\r\L" &
      "content-encoding: gzip\r\L" &
      "date: Mon, 21 Oct 2013 20:13:22 GMT\r\L"

suite "Encoder - Response Examples with Huffman Coding":
  var dh = initDynHeaders(256)

  test "First Response":
    var
      ic = newSeq[byte]()
      expected = @[
        0x4882'u16, 0x6402, 0x5885, 0xaec3,
        0x771a, 0x4b61, 0x96d0, 0x7abe,
        0x9410, 0x54d4, 0x44a8, 0x2005,
        0x9504, 0x0b81, 0x66e0, 0x82a6,
        0x2d1b, 0xff6e, 0x919d, 0x29ad,
        0x1718, 0x63c7, 0x8f0b, 0x97c8,
        0xe9ae, 0x82ae, 0x43d3].toBytes
      hs = [
        [":status", "302"],
        ["cache-control", "private"],
        ["date", "Mon, 21 Oct 2013 20:13:21 GMT"],
        ["location", "https://www.example.com"]]
    for h in hs:
      hencode(h[0], h[1], dh, ic)
    check ic == expected
    check $dh ==
      "location: https://www.example.com\r\L" &
      "date: Mon, 21 Oct 2013 20:13:21 GMT\r\L" &
      "cache-control: private\r\L" &
      ":status: 302\r\L"

  test "Second Response":
    var
      ic = newSeq[byte]()
      expected = @[
        0x4883'u16, 0x640e, 0xffc1, 0xc0bf].toBytes
      hs = [
        [":status", "307"],
        ["cache-control", "private"],
        ["date", "Mon, 21 Oct 2013 20:13:21 GMT"],
        ["location", "https://www.example.com"]]
    for h in hs:
      hencode(h[0], h[1], dh, ic)
    check ic == expected
    check $dh ==
      ":status: 307\r\L" &
      "location: https://www.example.com\r\L" &
      "date: Mon, 21 Oct 2013 20:13:21 GMT\r\L" &
      "cache-control: private\r\L"

  test "Third Response":
    var
      ic = newSeq[byte]()
      expected = @[
        0x88c1'u16, 0x6196, 0xd07a, 0xbe94,
        0x1054, 0xd444, 0xa820, 0x0595,
        0x040b, 0x8166, 0xe084, 0xa62d,
        0x1bff, 0xc05a, 0x839b, 0xd9ab,
        0x77ad, 0x94e7, 0x821d, 0xd7f2,
        0xe6c7, 0xb335, 0xdfdf, 0xcd5b,
        0x3960, 0xd5af, 0x2708, 0x7f36,
        0x72c1, 0xab27, 0x0fb5, 0x291f,
        0x9587, 0x3160, 0x65c0, 0x03ed,
        0x4ee5, 0xb106, 0x3d50].toBytes
    expected.add(byte 0x07'u8)
    var
      hs = [
        [":status", "200"],
        ["cache-control", "private"],
        ["date", "Mon, 21 Oct 2013 20:13:22 GMT"],
        ["location", "https://www.example.com"],
        ["content-encoding", "gzip"],
        ["set-cookie",
         "foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; max-age=3600; version=1"]]
    for h in hs:
      hencode(h[0], h[1], dh, ic)
    check ic == expected
    check $dh ==
      "set-cookie: foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; " &
      "max-age=3600; version=1\r\L" &
      "content-encoding: gzip\r\L" &
      "date: Mon, 21 Oct 2013 20:13:22 GMT\r\L"

suite "Uncategorized tests":
  test "Empty header value":
    var dh = initDynHeaders(4096)
    var ic = newSeq[byte]()
    hencode("pragma", "", dh, ic, huffman = false)
    var d = initDecodedStr()
    dh.reset()
    hdecodeAll(ic, dh, d)
    check $d == "pragma: \r\n"
    check $dh == "pragma: \r\n"

  test "Empty header value huffman":
    var dh = initDynHeaders(4096)
    var ic = newSeq[byte]()
    hencode("pragma", "", dh, ic, huffman = true)
    var d = initDecodedStr()
    dh.reset()
    hdecodeAll(ic, dh, d)
    check $d == "pragma: \r\L"
    check $dh == "pragma: \r\L"

  test "Dynamic table size update":
    var ic = newSeq[byte]()
    check signalDynTableSizeUpdate(ic, 256) == 3
    check ic.len == 3
    var d = initDecodedStr()
    var dh = initDynHeaders(4096)
    var dhSize = 0
    hdecodeAll(ic, dh, d, dhSize)
    check dhSize == 256
    check $d == ""
    check $dh == ""
  
  test "encodeLastResize no resize":
    var ic = newSeq[byte]()
    var dh = initDynHeaders(4096)
    check encodeLastResize(dh, ic) == 0
    check ic.len == 0

  test "encodeLastResize resize to 0":
    var dh = initDynHeaders(4096)
    dh.setSize 0
    var ic2 = newSeq[byte]()
    let expected = signalDynTableSizeUpdate(ic2, 0)
    var ic = newSeq[byte]()
    check encodeLastResize(dh, ic) == expected
    check ic == ic2

  test "encodeLastResize resize to 0 and 4096":
    var dh = initDynHeaders(4096)
    dh.setSize 0
    dh.setSize 4096
    var ic2 = newSeq[byte]()
    let expected =
      signalDynTableSizeUpdate(ic2, 0) +
      signalDynTableSizeUpdate(ic2, 4096)
    var ic = newSeq[byte]()
    check encodeLastResize(dh, ic) == expected
    check ic == ic2

  test "encodeLastResize multi resizes":
    var dh = initDynHeaders(4096)
    dh.setSize 0
    dh.setSize 123
    dh.setSize 1024
    dh.setSize 2048
    dh.setSize 4096
    var ic2 = newSeq[byte]()
    let expected =
      signalDynTableSizeUpdate(ic2, 0) +
      signalDynTableSizeUpdate(ic2, 4096)
    var ic = newSeq[byte]()
    check encodeLastResize(dh, ic) == expected
    check ic == ic2

  test "clearLastResize":
    var dh = initDynHeaders(4096)
    dh.setSize 0
    var ic = newSeq[byte]()
    check encodeLastResize(dh, ic) == 1
    check ic.len == 1
    check encodeLastResize(dh, ic) == 1
    check ic.len == 2
    check encodeLastResize(dh, ic) == 1
    check ic.len == 3
    dh.clearLastResize()
    ic.setLen 0
    check encodeLastResize(dh, ic) == 0
    check ic.len == 0

  test "Encoded update signal":
    # encoder
    var encDh = initDynHeaders(4096)
    encDh.setSize 1024
    var ic = newSeq[byte]()
    discard encodeLastResize(encDh, ic)
    # decoder
    var decDh = initDynHeaders(4096)
    check decDh.finalSetSize == 4096
    var d = initDecodedStr()
    hdecodeAll(ic, decDh, d)
    check decDh.finalSetSize == 1024

  test "Encoded update signal tries to exceed the max size":
    var encDh = initDynHeaders(4096)
    encDh.setSize 100_000
    var ic = newSeq[byte]()
    discard encodeLastResize(encDh, ic)
    var decDh = initDynHeaders(4096)
    var d = initDecodedStr()
    doAssertRaises(DecodeError):
      hdecodeAll(ic, decDh, d)
