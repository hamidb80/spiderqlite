func last*[T](s: openArray[T]): T = 
  s[^1]

func empty*[T: string or seq](s: T): bool = 
  0 == len s

func prune*(s: var seq) = 
  s.del s.high


template raisee*(reason): untyped =
  ## raise [e]rror -- just a convention
  raise newException(ValueError, reason)
  
  
func isSubOf*(a, b: seq): bool =
  for c in a:
    if c notin b:
      return false
  true
