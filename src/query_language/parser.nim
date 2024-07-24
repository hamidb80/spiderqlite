import std/[strutils, options]

import ../utils/other

import questionable
# import pretty


type
  LexKind = enum
    lkComment

    lkSep
    lkIndent
    lkDeIndent

    lkHashTag
    lkAtSign
    
    lkIdent
    lkInt
    lkFloat
    lkStr
    
    lkAbs
    lkDot

    lkOperator

  # FilePos = tuple
  #   line, col: Natural

  Token = object
    # loc: Slice[File2dPos]

    case kind: LexKind 
    of lkInt:
      ival: int
    
    of lkFloat:
      fval: float
    
    of lkOperator, lkStr, lkIdent, lkAbs:
      sval: string
    
    else: 
      discard
  

  Spqlkind* = enum
    gkDef         # #tag
    gkFieldPred   # inside def
    gkAsk         # ask [query]
    gkReturn      # return
    gkUpdate      # update
    gkDelete      # delete

    gkCase
    gkWhen
    gkElse

    gkUnique      # unique

    gkTypes       # types
    gkSort        # sort

    gkInsert      # insert node

    gkDeleteIndex # delete index
    gkCreateIndex # create index

    gkListIndexes # list indexes

    gkInfix       # a + 2
    gkPrefix      # not good

    gkIdent       # name
    gkIntLit      # 13
    gkFloatLit    # 3.14
    gkBool        # true false
    gkStrLit      # "salam"

    gkNull        # .
    gkInf         # inf

    gkVar         # |var|
    gkChain       # 1-r->p

    gkParams
    gkUse
    gkGroupBy     # GROUP BY
    gkTake        # select take
    gkFrom        # from
    gkHaving      # HAVING
    gkOrderBy     # ORDER BY
    gkLimit       # LIMIT
    gkOffset      # OFFSET
    gkAlias       # AS; named expressions
    gkCall        # count(a)

    gkComment     # --

    gkFieldAccess # .field

    gkWrapper

  GqlDefKind* = enum
    defNode
    defEdge

  SpqlNode* = ref object
    children*: seq[SpqlNode]

    case kind*: Spqlkind
    of gkDef:
      defKind*: GqlDefKind

    of gkIdent, gkStrLit, gkComment, gkVar:
      sval*: string

    of gkIntLit:
      ival*: int

    of gkFloatLit:
      fval*: float

    of gkBool:
      bval*: bool

    else:
      discard



using 
  str: string
  starti: int


func firstLineIndentation(str): tuple[indent, firstCharIndex: Natural] = 
  var 
    lineStartIndex = 0
    ind            = 0

  # skips empty lines
  for i, ch in str:
    if ch == '\n':
      lineStartIndex = i+1
      ind            = 0
    
    elif ch == ' ':
      inc ind
    
    else:
      return (ind, i)
  
  raisee "N/A"


func skipSpaces(str; starti): Natural = 
  for i in starti..str.high:
    if str[i] == ' ':
      inc result
    else:
      break

func parseIdent(str; starti): Natural = 
  for i in starti..str.high:
    if str[i] in Whitespace:
      return i - starti - 1
  return str.len - starti - 1

func parseString(str; starti): Natural = 
  var escaped = false
  
  for i in starti+1..str.high:
    case str[i]
    of '\\': 
      escaped = not escaped
    
    of '"': 
      if not escaped:
        return i - starti

      escaped = false

    else:
      escaped = false

func tryParseInt(str): Option[int] = 
  try:
    some parseInt str
  except:
    none int

func tryParseFloat(str): Option[float] = 
  try:
    some parseFloat str
  except:
    none float

func `{}`(str; i: int): char = 
  if likely i < str.len: str[i]
  else:                  '\n'


func gWrapper: SpqlNode = 
  SpqlNode(kind: gkWrapper) 


func lexSpql(content: string): seq[Token] = 
  let
    indentInfo = firstLineIndentation content

  var 
    sz            = len content
    i             = indentInfo.firstCharIndex
    indLevels     = @[indentInfo.indent]
    lastLineIndex = 0

  # for i, ch in content:
  #   debugEcho (i, ch)

  # debugEcho "------------------"

  while i <= sz:
    let ch = content{i}
    # debugEcho (i, ch)

    case ch

    of '\n':
      lastLineIndex = i
      ++ i
      << Token(kind: lkSep)

    of ' ':
      let step = skipSpaces(content, i)

      if content{i+step} != '\n':
        if i == lastLineIndex+1:
          if indLevels[^1] < step:
            << Token(kind: lkIndent)
            indLevels.add step

          else:
            while (not empty indLevels) and (step < indLevels[^1]):
              << Token(kind: lkDeIndent)
              indLevels.less

      inc i, step

    of '#':
      << Token(kind: lkHashTag)
      ++i
    
    of '@':
      << Token(kind: lkAtSign) 
      ++i
  
    of '.':
      << Token(kind: lkDot)
      ++i
  
    of Letters, '_', '/', '+', '=', '<', '>', '^', '~', '$', '[', '{', '(':
      let 
        size = parseIdent(content, i)
        word = content[i..i+size]
      
      << Token(kind: lkIdent, sval: word)
      inc i, size+1

    of Digits:
      let 
        size = parseIdent(content, i)
        word = content[i..i+size]

      # int
      if val =? tryParseInt word:
        << Token(kind: lkInt, ival: val)

      # float
      elif val =? tryParseFloat word:
        << Token(kind: lkFloat, fval: val)

      # ident e.g. 0a
      else:
        << Token(kind: lkIdent, sval: word)

      inc i, size+1

    of '"':
      let step = parseString(content, i)
      << Token(kind: lkStr, sval: content[i+1..i+step-1])
      inc i, step+1

    of '|': 
      # string concat opertor ||
      if content{i+1} == '|':
        << Token(kind: lkOperator, sval: "||")
        inc i, 2

      # |var|
      else:
        let
          size = parseIdent(content, i)
          word = content[i+1..i+size-1]
        << Token(kind: lkAbs, sval: word)
        inc i, size+1

    of '-':
      # comment
      if content{i+1} == '-':
        let ni = find(content, '\n', i+2)
        
        i = 
          if ni == -1: content.high
          else:        ni

      # negative number(float or int)
      elif content{i+1} in Digits:
        let 
          size = parseIdent(content, i)
          word = content[i..i+size]

        if val =? tryParseInt word:
          << Token(kind: lkInt, ival: val)

        elif val =? tryParseFloat word:
          << Token(kind: lkFloat, fval: val)

        else:
          raisee "invalid ident: '" & word & "'"

        ++i
      
      # subtraction
      else:
        << Token(kind: lkOperator, sval: "-")
        ++i
    
    of '*':
      # multipication
      if content{i+1} in Whitespace:
        << Token(kind: lkOperator, sval: "*")
        ++i

      # ident e.g. *d
      else:
        let
          size = parseIdent(content, i)
          word = content[i..i+size]
        << Token(kind: lkIdent, sval: word)
        inc i, size+1

    else:
      # of '~', '`', ':', ';', '?', '%', ',', '!':
      raisee "invalid char: " & ch


template gNode*(k: Spqlkind, ch: seq[SpqlNode] = @[]): SpqlNode =
  SpqlNode(kind: k, children: ch)

template gIdent*(str): SpqlNode =
  SpqlNode(kind: gkIdent, sval: str)

template prefixNode*(str: string): SpqlNode =
  SpqlNode(kind: gkPrefix, children: @[gIdent str])

template infixNode*(str: string): SpqlNode =
  SpqlNode(kind: gkInfix, children: @[gIdent str])



func parseCallToJson*           (): SpqlNode =
  SpqlNode(
    kind: gkCall, 
    children: @[
      SpqlNode(kind: gkIdent, sval: "json")])

func parseCallToJsonObject*     (): SpqlNode =
  SpqlNode(
    kind: gkCall, 
    children: @[
      SpqlNode(kind: gkIdent, sval: "json_object")])

func parseCallToJsonObjectGroup*(): SpqlNode =
  SpqlNode(
    kind: gkCall, 
    children: @[
      SpqlNode(kind: gkIdent, sval: "json_group_object")])

func parseCallToJsonArray*      (): SpqlNode =
  SpqlNode(
    kind: gkCall, 
    children: @[
      SpqlNode(kind: gkIdent, sval: "json_array")])

func parseCallToJsonArrayGroup* (): SpqlNode =
  SpqlNode(
    kind: gkCall, 
    children: @[
      SpqlNode(kind: gkIdent, sval: "json_group_array")])


func parseSpQl(tokens: seq[Token]): SpqlNode = 
  var 
    node    = gWrapper()
    stack   = @[node]
    i       = 0
    isFirst = true
    isNode  = false

  template newNode(n): untyped =
    isNode = true
    node   = n

  while i < tokens.len:
    let t = tokens[i]

    # debugEcho (t, isFirst)
    # print stack[0]

    case t.kind
    of lkComment:  discard
    of lkSep:      discard

    of lkIndent:   
      let l = stack[^1].children[^1]
      stack.add l

    of lkDeIndent: 
      stack.less

    of lkDot:
      newNode SpqlNode(kind: gkFieldAccess)

    of lkHashTag:
      newNode SpqlNode(kind: gkDef, defKind: defNode)

    of lkAtSign:
      newNode SpqlNode(kind: gkDef, defKind: defEdge)


    of lkInt:
      newNode SpqlNode(kind: gkIntLit, ival: t.ival)

    of lkFloat:
      newNode SpqlNode(kind: gkFloatLit, fval: t.fval)

    of lkStr:
      newNode SpqlNode(kind: gkStrLit, sval: t.sval)

    of lkAbs: 
      newNode SpqlNode(kind: gkVar, sval: t.sval)

    of lkIdent, lkOperator:
      newNode:
        case t.sval.toUpperAscii
        of "ASK",  "MATCH",  "FROM":         gNode gkAsk
        of "TAKE", "SELECT", "RETURN", "RET":gNode gkTake

        of "PARAMS", "PARAMETERS":           gNode gkParams
        of "USE", "TEMPLATE":                gNode gkUse

        of "GROUP", "GROUP_BY", "GRP":       gNode gkGroupBy
        of "ORDER", "ORDER_BY", "ORD":       gNode gkOrderBy
        of "SORT", "SORT_BY"         :       gNode gkSort
        of "HAVING",            "HAV":       gNode gkHaving
        of "LIMIT",             "LIM":       gNode gkLimit
        of "OFFSET",            "OFF":       gNode gkOffset
        of "AS", "ALIAS", "ALIASES":         gNode gkAlias

        of "CASE":                           gNode gkCase
        of "WHEN":                           gNode gkWhen
        of "ELSE":                           gNode gkElse

        of "()":                             gNode gkCall
        of ">>":                             parseCallToJson()
        of "{}":                             parseCallToJsonObject()
        of "{}.":                            parseCallToJsonObjectGroup()
        of "[]":                             parseCallToJsonArray()
        of "[].":                            parseCallToJsonArrayGroup()

        of "||", "%",
          "=", "==", "!=",
          "<",  "<=",
          ">=", ">",
          "+" , "-",
          "*",  "/",
          
          "AND", "NAND",
          "OR",  "NOR",
          "XOR", 
          "IS", "ISNOT",
          # "IN", "NOTIN", 
          # "BETWEEN",
          "LIKE":                 infixNode  t.sval
   
        of "$", "NOT":            prefixNode t.sval
        
        else:
          # idents with dot: movie.id
          let parts = t.sval.split('.', maxsplit=1)

          SpqlNode(
            kind: gkIdent,
            sval: parts[0],
            children: 
              case parts.len
              of 1: @[]
              else: @[
                SpqlNode(
                  kind: gkFieldAccess,
                  children: @[
                    gIdent parts[1]])])

    ++i

    if isNode:
      if isFirst:
        add stack[^1].children,              node
      
      elif # to prevent [somehting .field] bug which `field` gets into `something` not `.`
        stack[^1].children[^1].children.len               >  0             and 
        stack[^1].children[^1].children[^1].kind          == gkFieldAccess and
        stack[^1].children[^1].children[^1].children.len  == 0
      :
        add stack[^1].children[^1].children[^1].children, node
      
      else:
        add stack[^1].children[^1].children, node

    isFirst = t.kind in {lkSep, lkIndent, lkDeIndent}
    isNode  = false

    # ignore:
    #   discard stdin.readLine

  stack[0]
  
func parseSpQl*(content: string): SpqlNode = 
  parseSpQl lexSpql content

