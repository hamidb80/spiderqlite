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
      let d = 
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
      elif tk.indent > 0:
        discard
      else: assert false, "WTF: " & line

# TODO match predefined patterns
#      A-B->C
#      A-B->C-D->A

when isMainModule:
  echo parseGql readFile "./play.sql"
