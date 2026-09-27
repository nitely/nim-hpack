# v0.5.0

* Performance: decoding is ~2x faster, encoding is ~3x-6x faster.
  See `nimble bench`
* Huffman decoding uses a lookup table decoding up to two symbols
  at a time; Huffman encoding uses a 64-bit accumulator
* The encoder finds headers through hash indexes instead of
  scanning the static and dynamic tables
* `DynHeaders` stores entries contiguously as `name: value\r\n` lines
* Breaking: removed `DynHeaders` `[]`, `items`, `pairs`, `substr`
  and `cmp`; use `find`, `findName`, `nameLen`, `lineLen`,
  `copyName`, `copyLine` and `addLine` instead
* Breaking: `DynHeaders` `==` compares the entries and sizes
  instead of the internal representation
* Breaking: `huffman_data` contains the RFC code table (`hcCodes`)
  instead of the decoding state machine
* Breaking: `hcencode` and `hcencodeLen` return `int`
* Added `hcdecode` overload decoding into an `openArray[char]`,
  and `hcdecodeMaxLen`

# v0.4.0

* Removed DecodedStr
* Removed deprecated procs

# v0.3.3

* Resize improvements

# v0.3.2

* Resize bug fix

# v0.3.1

* Bug fix #3

# v0.3.0

* Improve resize & remove number of headers limit #2

# v0.2.0

* Use `Natural` instead of `int` where possible
* Make `hencode` discardable
* Drop support for Nim 0.18

# v0.1.1

* Deprecated `reset`, use `clear` instead
* Deprecated `hdecode` and `hdecodeAll`
  not taking the dynamic header size

# v0.1

* Initial release
