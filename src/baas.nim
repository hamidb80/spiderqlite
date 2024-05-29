import std/[macros]
import std/[strutils, sequtils, paths, strscans]
import lowdb/sqlite
import iterrr


template withDb(path, ident, body): untyped =
  let ident = open(path, "", "", "")
  body
  close db

template p(strPath): untyped =
  Path strPath

template readFile(p: Path): untyped =
  readfile string p
  

# template `~>`(collection, op): untyped =
#   collection.mapit op it

# template `~.`(a, b): untyped =
#   cast[seq[a]](b)

func empty(s: string): bool = 
  0 == len s

proc sep(sqls: SqlQuery): seq[SqlQuery] = 
  iterrr sqls.string.split ';':
    map    strip     it
    filter not empty it
    map    sql       it
    toseq()

proc loadSql(path: Path): SqlQuery = 
  sql readFile path

proc loadSqls(path: Path): seq[SqlQuery] = 
  sep loadSql path

proc exec(db: DbConn, sqls: seq[SqlQuery]) = 
  for s in sqls:
    if s.string.len != 0:
      db.exec s


func sqlize*[T](items: seq[T]): string =
  '(' & join(items, ", ") & ')'

type
  QueryPart = enum
    putLit
    putExpr
    putValue

proc sqlToFnImpl(str: string): NimNode =
    let
        minLen = 3 * len str
        res    = genSym(nskVar, "sqlFmtTemp")
    var 
        opened = '.'
        lasti  = -1
        acc: seq[tuple[window: Slice[int], kind: QueryPart]]

    template cond(check, repl, action): untyped =
      if opened == check:
          acc.add (lasti+1 .. i-1, action)
          opened = repl
          lasti  = i

    for i, ch in str:
        case ch
        of '[', '{': cond '.', ch , putLit
        of ']':      cond '[', '.', putExpr
        of '}':      cond '{', '.', putValue
        else:        discard
    add acc, (lasti+1 .. str.len-1, putLit)


    var code = newStmtList()

    for i in acc:
      let  
        s = str[i.window]
        k = i.kind
        d = 
          if k == putLit: newLit    s
          else:           parseExpr s 
      
      # echo repr s, ' ', i.kind

      case k
      of putLit  :       
          code.add quote do:
            add `res`, `d`
      of putExpr :       
          code.add quote do:
            add `res`, $`d`
      of putValue:       
          code.add quote do:
            add `res`, $dbvalue(`d`)

    result = quote:
      block:
        var `res` = newStringOfCap `minLen`
        `code`
        sql `res`

    debugEcho repr result

macro fsql*(str: static string): untyped =
    ## strformat for sql
    ## []: raw value
    ## {}: formatted sql, replaced with `?`
    
    sqlToFnImpl str


type 
  ProcParam = object
    name: string
    typ:  string

  SqlProc = object
    sql:    string
    params: seq[ProcParam]

proc parseSqlProc(content: string): SqlProc = 
  for l in splitLines content:
    if l.startsWith "-- ":
      var pp: ProcParam
      if scanf(l, "-- $w$s:$s$w", pp.name, pp.typ):
        add result.params, pp
      else:
        assert false, "bad sql param: " & l
    else:
      add result.sql, l


when isMainModule:
    let
        name = "hamid"
        age = 22

    echo string fsql """
        UPDATE Tag SET 
        name = {name}, 
        age  = {age}
        ;
        """ 

    echo parseSqlProc readFile "./sql/procs/createNode.sql"

when isMainModule:
  echo "what the hell"
  discard stdin.readline
  withDb "play.db", db:
    db.exec loadSqls p"./sql/schema.sql"
    echo db.insertId(loadSql p"./sql/procs/createNode.sql", "person", "1")
    echo "???"
