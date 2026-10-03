{.push raises: [].}

template setLenUninit2*(s, newlen: untyped): untyped =
  when (NimMajor, NimMinor, NimPatch) >= (2, 2, 10):
    setLenUninit(s, newlen)
  else:
    setLen(s, newlen)
