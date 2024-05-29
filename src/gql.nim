import std/[strutils]

type
  GqlOperator = enum
    goLess
    goLessEq
    goEq
    goNotEq
    goMoreEq
    goMore
    goPlus
    goMinus
    goMult
    goDiv
    goMod
    goAnd
    goOr
    goIn
    goNotIn
    goEmpty     # empty?
    goCheckNull # null?
    # goGroup     # (...)

  GqlKind = enum
    gkDataDef
    gkFieldPred
    gkAsk
    gkReturn
    gkUpdate
    gkDelete
    
    gkTypes
    
    gkInsertNode
    gkInsertEdge
    
    gkDeleteIndex
    gkCreateIndex

    gkListIndexes

    gkInfix
    gkPrefix

    gkIdent
    gkIntLit
    gkStrLit
    gkChain # 1-:-p

    gkNull # :
    gkTrue
    gkFalse

    gkVar # |var|
    # gkFnCall

  GqlNode = object
    kind: GqlKind


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
      case tk.key
      of "#":       add result, GqlNode(kind: gkDataDef)
      of "ASK" :    add result, GqlNode(kind: gkAsk)
      of "RETURN":  add result, GqlNode(kind: gkReturn)
      of "SELECT":  discard
      of "INSERT":  discard
      of "UPDATE":  discard
      of "LIST":    discard
      of "CREATE":  discard
      of "DELETE":  discard
      of "FIELDS":  discard
      of "--": discard
      elif tk.indent > 0:
        discard
      else: assert false, "WTF: " & line


when isMainModule:
  echo parseGql readFile "./play.sql"
