import std/[strutils]

type
  GqlOperator = enum
    goLess  # <
    goLessEq # <=
    goEq # = 
    goNotEq # !=
    goMoreEq # >=
    goMore # >
    goPlus # +
    goMinus # -
    goMult # *
    goDiv # /
    goMod # %
    goIn  # in
    goNotIn # notin
    goEmpty     # empty?
    goCheckNull # null?

    goAnd # and
    goOr  # or
    goUnion # union
    goSubtract # subtract
    goGroup # (a b c)

  GqlKind = enum
    gkDef # #tag
    gkFieldPred # inside def
    gkAsk # ask [limit] [offset] query
    gkReturn # return
    gkUpdate # update
    gkDelete # delete
    
    gkUnique # unique
    
    gkTypes # types
    gkSort  # sort
    
    gkInsertNode # insert node
    gkInsertEdge # insert edge
    
    gkDeleteIndex # delete index 
    gkCreateIndex # create index 

    gkListIndexes # list indexes

    gkInfix # a + 2
    gkPrefix # not good

    gkIdent # name
    gkIntLit # 13
    gkStrLit # "salam"
    gkChain # 1-:->p

    gkNull # :
    gkBool # true false
    gkInf # inf

    gkVar # |var|

    gkSelect # select

    gkNameSpace # namespace
    gkDataBase # database
    gkStructure # structure, struct, table, object, obj
    gkRelation  # references, ref, rel, relation
    gkProcedure # procedure, proc
    gkFrom # from
    gkLimit # limit
    gkComment # --

    gkIdSpecifier # @ID
    gkFieldAccess # table.field


  GqlNode = object
    kind: GqlKind
    children: seq[GqlNode]


func cmd(line: string): tuple[indent: Natural, key: string] = 
  let
    ind = indentation line
    tmp = line.substr ind
    cmd = 
      if   tmp[0] == '#': "#"
      else              : toUpper tmp.split[0]
  
  (ind, cmd)

proc parseGql(content: string): seq[GqlNode] = 
  for line in splitLines content:
    if not isEmptyOrWhitespace line:
      let tk = cmd line
      discard 
        case tk.key
        of "#":          gkDef
        of "ASK" :       gkAsk
        of "DATABASE":   gkDataBase
        of "TABLE"   :   gkStructure
        of "REFERENCES": gkRelation
        of "NAMESPACE":  gkNameSpace
        of "PROC":       gkProcedure
        of "SELECT":     gkSelect
        of "FROM":       gkFrom
        of "LIMIT":      gkLimit
        of "--":         gkComment
        else: raise newException(ValueError, "")
      # of "RETURN":     gkReturn
      # of "INSERT":     gkInsert
      # of "CREATE":     discard
      # of "DELETE":     discard
      # of "FIELDS":     discard
      # of "UPDATE":    gkUpdate
      # of "LIST"  :    
      # elif tk.indent > 0:
      #   discard
      # else: assert false, "WTF: " & line

func qp(s: string): string = s


const predefinedQueryPatterns = {
  qp"A-B->C":      1,
  qp"A-B->C-D->A": 2
}

discard """
  SELECT 
    p
  FROM 
    nodes p
  JOIN 
    edges a,
    edges c,
    nodes t
  ON
    a.tag    == 'assigned_to'  AND
    a.source == p.id           AND
    a.target == t.id           
    AND
    c.tag    == 'completed_by' AND
    c.source == t.id           AND
    c.target != m.id           
  WHERE 
    p.id     == |id|
"""

func matches(pattern, query: string): bool = 
  false

proc goGql(q: string) = 
  for (p, a) in predefinedQueryPatterns:
    if matches(p, q):
      discard

when isMainModule:
  echo parseGql readFile "./play.sql"
