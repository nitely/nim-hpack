# v0.6.0

* Bytes APIs
* Breaking changes:
  * Rename DynHeaders -> Hpack
  * Rename initDynHeaders -> initHpack
  * Rename HBounds -> HpackBound
  * `hpack` no longer exports `hpack/hcollections`

# v0.5.0

* Bug fixes for Nim >= 2.2.8
* Perf improvements

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
