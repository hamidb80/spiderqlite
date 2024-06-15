import std/[tables, sequtils]
import db_connector/db_sqlite


# funcs ----------------------------------------

# ---- convertor

func `$`*(s: SqlQuery): string =
  s.string

# ---- numbers

func evenp*(n: int): bool = 
  n mod 2 == 0

func oddp*(n: int): bool = 
  not evenp n

func `mod`*[M: static int](n: int, m: type M): range[0 .. M-1] = 
  system.`mod` n, m

# ---- seq

func last*[T](s: openArray[T]): T = 
  s[^1]

func empty*[T: string or seq](s: T): bool = 
  0 == len s

func less*[C: seq or string](s: var C) = 
  s.setLen s.len - 1

func more*(s: var seq) = 
  s.setLen s.len + 1

iterator rest*[T](s: seq[T]): T = 
  for i in 1..s.high:
    yield s[i]

func rest*(s: seq): seq = 
  s[1..^1]


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

# procs ----------------------------------------

proc openSqliteDB*(path: string): DbConn = 
  open path, "", "", ""

iterator times*(n: int): int = 
  for i in 0..<n:
    yield i

# templates ----------------------------------------

template inspect*(a): untyped =
  let b = a
  debugecho b
  b

template raisee*(reason): untyped =
  ## raise [e]rror -- just a convention
  raise newException(ValueError, reason)
  
template ignore*(body): untyped {.dirty.} =
  {.cast(nosideeffect).}:
    body

template `<<`*(thing): untyped {.dirty.} =
  add result, thing

template `~>`*(lst, op): untyped =
  lst.mapit op
  
template iff*(cond, iftrue, iffalse): untyped =
  if cond: iftrue
  else   : iffalse

template `=??`*(optional): untyped =
  var it {.inject.} = optional
  issome it
  
template `*<`*(val, n): untyped =
  val.repeat n

template findit*(s, cond): untyped =
  var i = -1
  for j, it {.inject.} in s:
    if cond:
      i = j 
      break
  i


template unwrap*(name, body): untyped =
  body
  