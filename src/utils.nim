import std/[tables, sequtils]
import db_connector/db_sqlite


func `$`*(s: SqlQuery): string =
  s.string


func last*[T](s: openArray[T]): T = 
  s[^1]

func empty*[T: string or seq](s: T): bool = 
  0 == len s

func prune*(s: var seq) = 
  s.del s.high


template raisee*(reason): untyped =
  ## raise [e]rror -- just a convention
  raise newException(ValueError, reason)
  
  

func isSubsetOf[T](a, b: seq[T]): bool =
  for c in a:
    if c notin b:
      return false
  true

func `<=`*[T](a, b: seq[T]): bool =
  isSubsetOf a, b

func map*[A, B](s: seq[A], t: Table[A, B]): seq[B] =
  s.mapit t[it]

func rev*[A, B](tab: Table[A, B]): Table[B, A] = 
  for k, v in tab:
    result[v] = k


iterator rest*[T](s: seq[T]): T = 
  for i in 1..s.high:
    yield s[i]

func rest*(s: seq): seq = 
  s[1..^1]


template ignore*(body): untyped {.dirty.} =
  {.cast(nosideeffect).}:
    body

# template inspect*(a): untyped =
#   debugecho a
#   a


template iff*(cond, iftrue, iffalse): untyped =
  if cond: iftrue
  else   : iffalse
  