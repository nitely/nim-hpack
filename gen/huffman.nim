## Huffman decoding using partial-decodig tables (Choueka variant)

const rawHC = """
    (  0)  |11111111|11000                             1ff8  [13]
    (  1)  |11111111|11111111|1011000                7fffd8  [23]
    (  2)  |11111111|11111111|11111110|0010         fffffe2  [28]
    (  3)  |11111111|11111111|11111110|0011         fffffe3  [28]
    (  4)  |11111111|11111111|11111110|0100         fffffe4  [28]
    (  5)  |11111111|11111111|11111110|0101         fffffe5  [28]
    (  6)  |11111111|11111111|11111110|0110         fffffe6  [28]
    (  7)  |11111111|11111111|11111110|0111         fffffe7  [28]
    (  8)  |11111111|11111111|11111110|1000         fffffe8  [28]
    (  9)  |11111111|11111111|11101010               ffffea  [24]
    ( 10)  |11111111|11111111|11111111|111100      3ffffffc  [30]
    ( 11)  |11111111|11111111|11111110|1001         fffffe9  [28]
    ( 12)  |11111111|11111111|11111110|1010         fffffea  [28]
    ( 13)  |11111111|11111111|11111111|111101      3ffffffd  [30]
    ( 14)  |11111111|11111111|11111110|1011         fffffeb  [28]
    ( 15)  |11111111|11111111|11111110|1100         fffffec  [28]
    ( 16)  |11111111|11111111|11111110|1101         fffffed  [28]
    ( 17)  |11111111|11111111|11111110|1110         fffffee  [28]
    ( 18)  |11111111|11111111|11111110|1111         fffffef  [28]
    ( 19)  |11111111|11111111|11111111|0000         ffffff0  [28]
    ( 20)  |11111111|11111111|11111111|0001         ffffff1  [28]
    ( 21)  |11111111|11111111|11111111|0010         ffffff2  [28]
    ( 22)  |11111111|11111111|11111111|111110      3ffffffe  [30]
    ( 23)  |11111111|11111111|11111111|0011         ffffff3  [28]
    ( 24)  |11111111|11111111|11111111|0100         ffffff4  [28]
    ( 25)  |11111111|11111111|11111111|0101         ffffff5  [28]
    ( 26)  |11111111|11111111|11111111|0110         ffffff6  [28]
    ( 27)  |11111111|11111111|11111111|0111         ffffff7  [28]
    ( 28)  |11111111|11111111|11111111|1000         ffffff8  [28]
    ( 29)  |11111111|11111111|11111111|1001         ffffff9  [28]
    ( 30)  |11111111|11111111|11111111|1010         ffffffa  [28]
    ( 31)  |11111111|11111111|11111111|1011         ffffffb  [28]
' ' ( 32)  |010100                                       14  [ 6]
'!' ( 33)  |11111110|00                                 3f8  [10]
'"' ( 34)  |11111110|01                                 3f9  [10]
'#' ( 35)  |11111111|1010                               ffa  [12]
'$' ( 36)  |11111111|11001                             1ff9  [13]
'%' ( 37)  |010101                                       15  [ 6]
'&' ( 38)  |11111000                                     f8  [ 8]
''' ( 39)  |11111111|010                                7fa  [11]
'(' ( 40)  |11111110|10                                 3fa  [10]
')' ( 41)  |11111110|11                                 3fb  [10]
'*' ( 42)  |11111001                                     f9  [ 8]
'+' ( 43)  |11111111|011                                7fb  [11]
',' ( 44)  |11111010                                     fa  [ 8]
'-' ( 45)  |010110                                       16  [ 6]
'.' ( 46)  |010111                                       17  [ 6]
'/' ( 47)  |011000                                       18  [ 6]
'0' ( 48)  |00000                                         0  [ 5]
'1' ( 49)  |00001                                         1  [ 5]
'2' ( 50)  |00010                                         2  [ 5]
'3' ( 51)  |011001                                       19  [ 6]
'4' ( 52)  |011010                                       1a  [ 6]
'5' ( 53)  |011011                                       1b  [ 6]
'6' ( 54)  |011100                                       1c  [ 6]
'7' ( 55)  |011101                                       1d  [ 6]
'8' ( 56)  |011110                                       1e  [ 6]
'9' ( 57)  |011111                                       1f  [ 6]
':' ( 58)  |1011100                                      5c  [ 7]
';' ( 59)  |11111011                                     fb  [ 8]
'<' ( 60)  |11111111|1111100                           7ffc  [15]
'=' ( 61)  |100000                                       20  [ 6]
'>' ( 62)  |11111111|1011                               ffb  [12]
'?' ( 63)  |11111111|00                                 3fc  [10]
'@' ( 64)  |11111111|11010                             1ffa  [13]
'A' ( 65)  |100001                                       21  [ 6]
'B' ( 66)  |1011101                                      5d  [ 7]
'C' ( 67)  |1011110                                      5e  [ 7]
'D' ( 68)  |1011111                                      5f  [ 7]
'E' ( 69)  |1100000                                      60  [ 7]
'F' ( 70)  |1100001                                      61  [ 7]
'G' ( 71)  |1100010                                      62  [ 7]
'H' ( 72)  |1100011                                      63  [ 7]
'I' ( 73)  |1100100                                      64  [ 7]
'J' ( 74)  |1100101                                      65  [ 7]
'K' ( 75)  |1100110                                      66  [ 7]
'L' ( 76)  |1100111                                      67  [ 7]
'M' ( 77)  |1101000                                      68  [ 7]
'N' ( 78)  |1101001                                      69  [ 7]
'O' ( 79)  |1101010                                      6a  [ 7]
'P' ( 80)  |1101011                                      6b  [ 7]
'Q' ( 81)  |1101100                                      6c  [ 7]
'R' ( 82)  |1101101                                      6d  [ 7]
'S' ( 83)  |1101110                                      6e  [ 7]
'T' ( 84)  |1101111                                      6f  [ 7]
'U' ( 85)  |1110000                                      70  [ 7]
'V' ( 86)  |1110001                                      71  [ 7]
'W' ( 87)  |1110010                                      72  [ 7]
'X' ( 88)  |11111100                                     fc  [ 8]
'Y' ( 89)  |1110011                                      73  [ 7]
'Z' ( 90)  |11111101                                     fd  [ 8]
'[' ( 91)  |11111111|11011                             1ffb  [13]
'\' ( 92)  |11111111|11111110|000                     7fff0  [19]
']' ( 93)  |11111111|11100                             1ffc  [13]
'^' ( 94)  |11111111|111100                            3ffc  [14]
'_' ( 95)  |100010                                       22  [ 6]
'`' ( 96)  |11111111|1111101                           7ffd  [15]
'a' ( 97)  |00011                                         3  [ 5]
'b' ( 98)  |100011                                       23  [ 6]
'c' ( 99)  |00100                                         4  [ 5]
'd' (100)  |100100                                       24  [ 6]
'e' (101)  |00101                                         5  [ 5]
'f' (102)  |100101                                       25  [ 6]
'g' (103)  |100110                                       26  [ 6]
'h' (104)  |100111                                       27  [ 6]
'i' (105)  |00110                                         6  [ 5]
'j' (106)  |1110100                                      74  [ 7]
'k' (107)  |1110101                                      75  [ 7]
'l' (108)  |101000                                       28  [ 6]
'm' (109)  |101001                                       29  [ 6]
'n' (110)  |101010                                       2a  [ 6]
'o' (111)  |00111                                         7  [ 5]
'p' (112)  |101011                                       2b  [ 6]
'q' (113)  |1110110                                      76  [ 7]
'r' (114)  |101100                                       2c  [ 6]
's' (115)  |01000                                         8  [ 5]
't' (116)  |01001                                         9  [ 5]
'u' (117)  |101101                                       2d  [ 6]
'v' (118)  |1110111                                      77  [ 7]
'w' (119)  |1111000                                      78  [ 7]
'x' (120)  |1111001                                      79  [ 7]
'y' (121)  |1111010                                      7a  [ 7]
'z' (122)  |1111011                                      7b  [ 7]
'{' (123)  |11111111|1111110                           7ffe  [15]
'|' (124)  |11111111|100                                7fc  [11]
'}' (125)  |11111111|111101                            3ffd  [14]
'~' (126)  |11111111|11101                             1ffd  [13]
    (127)  |11111111|11111111|11111111|1100         ffffffc  [28]
    (128)  |11111111|11111110|0110                    fffe6  [20]
    (129)  |11111111|11111111|010010                 3fffd2  [22]
    (130)  |11111111|11111110|0111                    fffe7  [20]
    (131)  |11111111|11111110|1000                    fffe8  [20]
    (132)  |11111111|11111111|010011                 3fffd3  [22]
    (133)  |11111111|11111111|010100                 3fffd4  [22]
    (134)  |11111111|11111111|010101                 3fffd5  [22]
    (135)  |11111111|11111111|1011001                7fffd9  [23]
    (136)  |11111111|11111111|010110                 3fffd6  [22]
    (137)  |11111111|11111111|1011010                7fffda  [23]
    (138)  |11111111|11111111|1011011                7fffdb  [23]
    (139)  |11111111|11111111|1011100                7fffdc  [23]
    (140)  |11111111|11111111|1011101                7fffdd  [23]
    (141)  |11111111|11111111|1011110                7fffde  [23]
    (142)  |11111111|11111111|11101011               ffffeb  [24]
    (143)  |11111111|11111111|1011111                7fffdf  [23]
    (144)  |11111111|11111111|11101100               ffffec  [24]
    (145)  |11111111|11111111|11101101               ffffed  [24]
    (146)  |11111111|11111111|010111                 3fffd7  [22]
    (147)  |11111111|11111111|1100000                7fffe0  [23]
    (148)  |11111111|11111111|11101110               ffffee  [24]
    (149)  |11111111|11111111|1100001                7fffe1  [23]
    (150)  |11111111|11111111|1100010                7fffe2  [23]
    (151)  |11111111|11111111|1100011                7fffe3  [23]
    (152)  |11111111|11111111|1100100                7fffe4  [23]
    (153)  |11111111|11111110|11100                  1fffdc  [21]
    (154)  |11111111|11111111|011000                 3fffd8  [22]
    (155)  |11111111|11111111|1100101                7fffe5  [23]
    (156)  |11111111|11111111|011001                 3fffd9  [22]
    (157)  |11111111|11111111|1100110                7fffe6  [23]
    (158)  |11111111|11111111|1100111                7fffe7  [23]
    (159)  |11111111|11111111|11101111               ffffef  [24]
    (160)  |11111111|11111111|011010                 3fffda  [22]
    (161)  |11111111|11111110|11101                  1fffdd  [21]
    (162)  |11111111|11111110|1001                    fffe9  [20]
    (163)  |11111111|11111111|011011                 3fffdb  [22]
    (164)  |11111111|11111111|011100                 3fffdc  [22]
    (165)  |11111111|11111111|1101000                7fffe8  [23]
    (166)  |11111111|11111111|1101001                7fffe9  [23]
    (167)  |11111111|11111110|11110                  1fffde  [21]
    (168)  |11111111|11111111|1101010                7fffea  [23]
    (169)  |11111111|11111111|011101                 3fffdd  [22]
    (170)  |11111111|11111111|011110                 3fffde  [22]
    (171)  |11111111|11111111|11110000               fffff0  [24]
    (172)  |11111111|11111110|11111                  1fffdf  [21]
    (173)  |11111111|11111111|011111                 3fffdf  [22]
    (174)  |11111111|11111111|1101011                7fffeb  [23]
    (175)  |11111111|11111111|1101100                7fffec  [23]
    (176)  |11111111|11111111|00000                  1fffe0  [21]
    (177)  |11111111|11111111|00001                  1fffe1  [21]
    (178)  |11111111|11111111|100000                 3fffe0  [22]
    (179)  |11111111|11111111|00010                  1fffe2  [21]
    (180)  |11111111|11111111|1101101                7fffed  [23]
    (181)  |11111111|11111111|100001                 3fffe1  [22]
    (182)  |11111111|11111111|1101110                7fffee  [23]
    (183)  |11111111|11111111|1101111                7fffef  [23]
    (184)  |11111111|11111110|1010                    fffea  [20]
    (185)  |11111111|11111111|100010                 3fffe2  [22]
    (186)  |11111111|11111111|100011                 3fffe3  [22]
    (187)  |11111111|11111111|100100                 3fffe4  [22]
    (188)  |11111111|11111111|1110000                7ffff0  [23]
    (189)  |11111111|11111111|100101                 3fffe5  [22]
    (190)  |11111111|11111111|100110                 3fffe6  [22]
    (191)  |11111111|11111111|1110001                7ffff1  [23]
    (192)  |11111111|11111111|11111000|00           3ffffe0  [26]
    (193)  |11111111|11111111|11111000|01           3ffffe1  [26]
    (194)  |11111111|11111110|1011                    fffeb  [20]
    (195)  |11111111|11111110|001                     7fff1  [19]
    (196)  |11111111|11111111|100111                 3fffe7  [22]
    (197)  |11111111|11111111|1110010                7ffff2  [23]
    (198)  |11111111|11111111|101000                 3fffe8  [22]
    (199)  |11111111|11111111|11110110|0            1ffffec  [25]
    (200)  |11111111|11111111|11111000|10           3ffffe2  [26]
    (201)  |11111111|11111111|11111000|11           3ffffe3  [26]
    (202)  |11111111|11111111|11111001|00           3ffffe4  [26]
    (203)  |11111111|11111111|11111011|110          7ffffde  [27]
    (204)  |11111111|11111111|11111011|111          7ffffdf  [27]
    (205)  |11111111|11111111|11111001|01           3ffffe5  [26]
    (206)  |11111111|11111111|11110001               fffff1  [24]
    (207)  |11111111|11111111|11110110|1            1ffffed  [25]
    (208)  |11111111|11111110|010                     7fff2  [19]
    (209)  |11111111|11111111|00011                  1fffe3  [21]
    (210)  |11111111|11111111|11111001|10           3ffffe6  [26]
    (211)  |11111111|11111111|11111100|000          7ffffe0  [27]
    (212)  |11111111|11111111|11111100|001          7ffffe1  [27]
    (213)  |11111111|11111111|11111001|11           3ffffe7  [26]
    (214)  |11111111|11111111|11111100|010          7ffffe2  [27]
    (215)  |11111111|11111111|11110010               fffff2  [24]
    (216)  |11111111|11111111|00100                  1fffe4  [21]
    (217)  |11111111|11111111|00101                  1fffe5  [21]
    (218)  |11111111|11111111|11111010|00           3ffffe8  [26]
    (219)  |11111111|11111111|11111010|01           3ffffe9  [26]
    (220)  |11111111|11111111|11111111|1101         ffffffd  [28]
    (221)  |11111111|11111111|11111100|011          7ffffe3  [27]
    (222)  |11111111|11111111|11111100|100          7ffffe4  [27]
    (223)  |11111111|11111111|11111100|101          7ffffe5  [27]
    (224)  |11111111|11111110|1100                    fffec  [20]
    (225)  |11111111|11111111|11110011               fffff3  [24]
    (226)  |11111111|11111110|1101                    fffed  [20]
    (227)  |11111111|11111111|00110                  1fffe6  [21]
    (228)  |11111111|11111111|101001                 3fffe9  [22]
    (229)  |11111111|11111111|00111                  1fffe7  [21]
    (230)  |11111111|11111111|01000                  1fffe8  [21]
    (231)  |11111111|11111111|1110011                7ffff3  [23]
    (232)  |11111111|11111111|101010                 3fffea  [22]
    (233)  |11111111|11111111|101011                 3fffeb  [22]
    (234)  |11111111|11111111|11110111|0            1ffffee  [25]
    (235)  |11111111|11111111|11110111|1            1ffffef  [25]
    (236)  |11111111|11111111|11110100               fffff4  [24]
    (237)  |11111111|11111111|11110101               fffff5  [24]
    (238)  |11111111|11111111|11111010|10           3ffffea  [26]
    (239)  |11111111|11111111|1110100                7ffff4  [23]
    (240)  |11111111|11111111|11111010|11           3ffffeb  [26]
    (241)  |11111111|11111111|11111100|110          7ffffe6  [27]
    (242)  |11111111|11111111|11111011|00           3ffffec  [26]
    (243)  |11111111|11111111|11111011|01           3ffffed  [26]
    (244)  |11111111|11111111|11111100|111          7ffffe7  [27]
    (245)  |11111111|11111111|11111101|000          7ffffe8  [27]
    (246)  |11111111|11111111|11111101|001          7ffffe9  [27]
    (247)  |11111111|11111111|11111101|010          7ffffea  [27]
    (248)  |11111111|11111111|11111101|011          7ffffeb  [27]
    (249)  |11111111|11111111|11111111|1110         ffffffe  [28]
    (250)  |11111111|11111111|11111101|100          7ffffec  [27]
    (251)  |11111111|11111111|11111101|101          7ffffed  [27]
    (252)  |11111111|11111111|11111101|110          7ffffee  [27]
    (253)  |11111111|11111111|11111101|111          7ffffef  [27]
    (254)  |11111111|11111111|11111110|000          7fffff0  [27]
    (255)  |11111111|11111111|11111011|10           3ffffee  [26]
EOS (256)  |11111111|11111111|11111111|111111      3fffffff  [30]
"""

import re
import math
import strutils
import parseutils
import algorithm

proc parse(rawHC: string): seq[string] =
  result = newSeqOfCap[string](257)
  for b in findAll(rawHC, re"\|[|01]+"):
    var b = replace(b, "|", "")
    assert '|' notin b
    assert b notin result
    result.add(b)
  assert result.len == 257

type
  Ntype = enum
    ntNode
    ntValue
  Node = ref object
    case kind: Ntype
    of ntNode:
      nxt: seq[Node] not nil
      c: char
    of ntValue:
      v: int

proc newNode(c = '@'): Node =
  Node(kind: ntNode, nxt: @[], c: c)

proc newNodeValue(v: int): Node =
  Node(kind: ntValue, v: v)

proc put(n: var Node, c: char): Node =
  assert n.kind == ntNode
  for nn in n.nxt:
    if nn.kind == ntNode and nn.c == c:
      result = nn
      return
  result = newNode(c)
  n.nxt.add(result)

proc buildTrie(hc: seq[string]): Node =
  result = newNode()
  for sym, c in pairs(hc):
    var n = result
    for cc in c:
      n = n.put(cc)
    n.nxt.add(newNodeValue(sym))

proc strTree(result: var string, n: Node) =
  ## for debugging purposes
  assert(not n.isNil)
  if n.kind == ntValue:
    result.add("($#)" % $n.v)
    return
  result.add("[$#" % $n.c)
  assert len(n.nxt) <= 3
  for nn in n.nxt:
    result.add(' ')
    strTree(result, nn)
  result.add(']')

proc `$`(n: Node): string =
  ## for debugging purposes
  result = ""
  strTree(result, n)

#[
var root = buildTrie(parse(rawHC))
for n in root.nxt:
  echo $n
]#

type
  Flag = enum
    flgSym = 0x01
    flgContinue = 0x02
    flgDone = 0x04
  PartialCode = object
    nxt: int
    sym: int
    flags: set[Flag]
  Row = array[16, PartialCode]
  Table = seq[Row]

proc initPartialCode(): PartialCode =
  result.nxt = -1
  result.sym = -1

proc isEmpty(pc: PartialCode): bool =
  (pc.nxt == -1 and
   pc.sym == -1 and
   pc.flags.card == 0)

proc initRow(): Row =
  for i in 0 ..< len(result):
    result[i] = initPartialCode()

proc value(n: Node): int =
  ## Return sym or -1
  result = -1
  for nn in n.nxt:
    if nn.kind == ntValue:
      result = nn.v
      return

proc rootFrom(offset, b: int): int =
  ## Return root index from offset + bits
  if offset == 0:
    result = 0
    return
  result = b
  for i in 0 ..< offset:
    result = result + 2 ^ i

proc build(
    n: Node,
    pdt: var Table,
    bits: string,
    roots: seq[int],
    parent: int) =
  ## build codes
  assert n.kind == ntNode
  assert bits.len <= 4
  var
    bits = bits
    parent = parent
    b = 0
  bits.add(n.c)
  discard parseBin(bits, b)
  if value(n) != -1:
    assert len(bits) in {1 .. 4}
    let
      offset = 4 - len(bits)
      bb = b shl offset
    for i in 0 ..< 2 ^ offset:
      assert isEmpty(pdt[parent][bb + i])
      assert roots[rootFrom(offset, i)] != -1  # maybe
      pdt[parent][bb + i].sym = value(n)
      pdt[parent][bb + i].nxt = roots[rootFrom(offset, i)]
      pdt[parent][bb + i].flags.incl({flgContinue, flgSym})
      # padding
      if i == 0x0f shr len(bits):
        pdt[parent][bb + i].flags.incl(flgDone)
    return
  if bits.len == 4:
    assert isEmpty(pdt[parent][b])
    pdt.add(initRow())
    pdt[parent][b].nxt = pdt.high
    pdt[parent][b].flags.incl(flgContinue)
    parent = pdt.high
    bits = ""
  for nn in n.nxt:
    assert nn.kind == ntNode
    build(nn, pdt, bits, roots, parent)

proc build(
    n: Node,
    pdt: var Table,
    bits: string,
    roots: seq[int]) =
  ## build codes with offset
  if len(bits) == 3:
    return
  assert n.kind == ntNode
  var
    bits = bits
    b = 0
  bits.add(n.c)
  discard parseBin(bits, b)
  for nn in n.nxt:
    assert nn.kind == ntNode
    build(nn, pdt, bits, roots)
  for nn in n.nxt:
    assert nn.kind == ntNode
    build(nn, pdt, "", roots, roots[rootFrom(len(bits), b)])

proc build(
    n: Node,
    pdt: var Table,
    bits: string,
    roots: var seq[int]) =
  ## build roots
  if len(bits) == 3:
    return
  assert n.kind == ntNode
  var
    bits = bits
    b = 0
  bits.add(n.c)
  discard parseBin(bits, b)
  pdt.add(initRow())
  assert roots[rootFrom(len(bits), b)] == -1
  roots[rootFrom(len(bits), b)] = pdt.high
  for nn in n.nxt:
    assert nn.kind == ntNode
    build(nn, pdt, bits, roots)

proc build(n: Node): Table =
  ##[
  Build partial decoding table.
  Codes are not of a fixed size,
  and while reading them they may contain the
  start of another code.

  Blocks from 0 to 2+4+8 are the initial states,
  one for each offset. The rest are continuations
  of partial codes. Each block has 16 states (2^4)
  and each index is a 4-bits partial code

  Sample table containing just ``100011`` code:

  offset|---------------0
     	  | ...
  1000	| (continues on 15)
        | ...
  	    |---------------X (2 blocks)
        | ...
  	    |---------------XX (4 blocks)
        | ...
        |---------------XXX (8 blocks)
        | ...
        |---------------15
  11XX| | (return sym and continues on XX)
        | ...
  ]##
  result = newSeqOfCap[Row](1_000)
  var roots = newSeq[int](15)
  for i in 0 ..< roots.len:
    roots[i] = -1
  result.add(initRow())
  roots[0] = result.high
  # build roots
  for nn in n.nxt:
    assert nn.kind == ntNode
    build(nn, result, "", roots)
  let r = roots
  # build offset codes
  for nn in n.nxt:
    assert nn.kind == ntNode
    build(nn, result, "", r)
  # build root codes
  for nn in n.nxt:
    assert nn.kind == ntNode
    build(nn, result, "", r, 0)
  # padding
  for i in 0 ..< 4:
    let offset = rootFrom(i, 0x0f shr (4 - i))
    result[roots[offset]][0x0f].flags.incl(flgDone)

proc toInt(f: set[Flag]): int =
  result = 0
  for ff in f:
    result = result or ff.ord

proc `$`(t: Table): string =
  var rows = newSeq[string]()
  for r in t:
    var row = newSeq[string]()
    for c in r:
      # EOS (256) is not allowed
      let
        sym = case c.sym
          of -1: 0
          of 256: 0
          else: c.sym
        flags = case c.sym
          of 256: {}
          else: c.flags
        nxt = case c.nxt
          of -1: 0
          else: c.nxt
      row.add(
        "[$#'u8, $#, $#]" % [
          $nxt, $sym, $toInt(flags)])
    rows.add("[\L    $#\L  ]" % join(row, ",\L    "))
  result = "[\L  $#\L]" % join(rows, ",\L  ")

type
  DecodeTable = seq[array[2, int]]

proc buildDecodeTable(s: seq[string]): DecodeTable =
  result = newSeq[array[2, int]](256)
  for i in 0 .. result.len-1:
    var b = 0
    assert parseBin(s[i], b) > 0
    result[i] = [b, s[i].len]

proc `$`(t: DecodeTable): string =
  result = "[\L"
  for row in t:
    result.add("  [$#'u32, $#'u32],\L" % [$row[0], $row[1]])
  result.add("]")

const hcTemplate = """# auto generated

type
  HcFlag* = enum
    hcfSym = $#
    hcfContinue = $#
    hcfDone = $#

const hcTable* = $#
const hcDecTable* = $#
"""

when isMainModule:
  let table = rawHC.parse.buildTrie.build
  echo table.len

  let decTable = rawHC.parse.buildDecodeTable

  var f = open("./src/hpack/huffman_data.nim", fmWrite)
  try:
    f.write(hcTemplate % [
      $flgSym.ord,
      $flgContinue.ord,
      $flgDone.ord,
      $table,
      $decTable])
  finally:
    close(f)

  block:
    echo "Test some codes"
    var nxt = 0
    nxt = table[nxt][0b1111].nxt
    nxt = table[nxt][0b1111].nxt
    nxt = table[nxt][0b1100].nxt
    assert table[nxt][0b0].sym == 0
    assert table[nxt][0b0111].sym == 0
    assert flgDone in table[nxt][0b0111].flags
    nxt = table[nxt][0b0111].nxt
    nxt = table[nxt][0b1111].nxt
    nxt = table[nxt][0b1111].nxt
    nxt = table[nxt][0b1111].nxt
    nxt = table[nxt][0b1101].nxt
    assert table[nxt][0b1000].sym == 1
    assert flgDone in table[nxt][0b1000].flags
