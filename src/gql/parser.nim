import std/[strutils, options]

import ../utils/other

import questionable
import pretty


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

  # FilePos = tuple
  #   line, col: Natural

  Token = object
    # loc: Slice[File2dPos]

    case kind: LexKind 
    of lkInt:
      ival: int
    
    of lkFloat:
      fval: float
    
    of lkStr, lkIdent, lkAbs:
      sval: string
    
    else: 
      discard
  

  GqlKind* = enum
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

  GqlNode* = ref object
    children*: seq[GqlNode]

    case kind*: GqlKind
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


func gWrapper: GqlNode = 
  GqlNode(kind: gkWrapper) 


func lexGql(content: string): seq[Token] = 
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
  
    of Letters, '/', '+', '=', '<', '>', '^', '~', '$', '[', '{', '(':
      let size = parseIdent(content, i)
      << Token(kind: lkIdent, sval: content[i..i+size])
      inc i, size+1

    of Digits:
      # ident or int or float

      let 
        size = parseIdent(content, i)
        word = content[i..i+size]

      if val =? tryParseInt word:
        << Token(kind: lkInt, ival: val)

      elif val =? tryParseFloat word:
        << Token(kind: lkFloat, fval: val)

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
        << Token(kind: lkIdent, sval: "||")
        inc i, 2

      # |var|
      else:
        let
          size = parseIdent(content, i)
          word = content[i..i+size]
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
        discard
        ++i
      
      # subtraction
      else:
        ++i
    
    of '*':
      # ident ( *d ) or multipication
      discard

    else:
      # of '~', '`', ':', ';', '?', '%', ',', '!':
      raisee "invalid char: " & ch


template gNode*(k: GqlKind, ch: seq[GqlNode] = @[]): GqlNode =
  GqlNode(kind: k, children: ch)

template gIdent*(str): GqlNode =
  GqlNode(kind: gkIdent, sval: str)

template prefixNode*(str: string): GqlNode =
  GqlNode(kind: gkPrefix, children: @[gIdent str])

template infixNode*(str: string): GqlNode =
  GqlNode(kind: gkInfix, children: @[gIdent str])



func parseCallToJson*           (): GqlNode =
  GqlNode(
    kind: gkCall, 
    children: @[
      GqlNode(kind: gkIdent, sval: "json")])

func parseCallToJsonObject*     (): GqlNode =
  GqlNode(
    kind: gkCall, 
    children: @[
      GqlNode(kind: gkIdent, sval: "json_object")])

func parseCallToJsonObjectGroup*(): GqlNode =
  GqlNode(
    kind: gkCall, 
    children: @[
      GqlNode(kind: gkIdent, sval: "json_group_object")])

func parseCallToJsonArray*      (): GqlNode =
  GqlNode(
    kind: gkCall, 
    children: @[
      GqlNode(kind: gkIdent, sval: "json_array")])

func parseCallToJsonArrayGroup* (): GqlNode =
  GqlNode(
    kind: gkCall, 
    children: @[
      GqlNode(kind: gkIdent, sval: "json_group_array")])


func parseGql(tokens: seq[Token]): GqlNode = 
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
      newNode GqlNode(kind: gkFieldAccess)

    of lkHashTag:
      newNode GqlNode(kind: gkDef, defKind: defNode)

    of lkAtSign:
      newNode GqlNode(kind: gkDef, defKind: defEdge)


    of lkInt:
      newNode GqlNode(kind: gkIntLit, ival: t.ival)

    of lkFloat:
      newNode GqlNode(kind: gkFloatLit, fval: t.fval)

    of lkStr:
      newNode GqlNode(kind: gkStrLit, sval: t.sval)

    of lkAbs: 
      newNode GqlNode(kind: gkVar, sval: t.sval)

    of lkIdent:
      newNode:
        case t.sval
        of "ASK", "MATCH", "FROM":           gNode gkAsk
        of "TAKE", "SELECT", "RETURN":       gNode gkTake

        of "PARAM", "PARAMS",  
          "PARAMETER", "PARAMETERS":         gNode gkParams
        
        of "USE", "TEMPLATE":                gNode gkUse

        of "GROUP", "GROUP_BY":              gNode gkGroupBy
        of "ORDER", "ORDER_BY":              gNode gkOrderBy

        of "SORT":                           gNode gkSort
        of "HAVING":                         gNode gkHaving
        of "LIMIT":                          gNode gkLimit
        of "OFFSET":                         gNode gkOffset
        of "AS", "ALIAS", "ALIASES":         gNode gkAlias

        of "CASE":                           gNode gkCase
        of "WHEN":                           gNode gkWhen
        of "ELSE":                           gNode gkElse

        of "()":                             gNode gkCall
        # special calls
        of ">>":                             parseCallToJson()
        of "{}":                             parseCallToJsonObject()
        of "{}.":                            parseCallToJsonObjectGroup()
        of "[]":                             parseCallToJsonArray()
        of "[].":                            parseCallToJsonArrayGroup()

        of "||", "%",
          "==", "!=",
          "<", "<=",
          ">=", ">",
          "+" , "-",
          "*", "/",
          "AND", "NAND",
          "OR", "NOR",
          "XOR", "IS", "ISNOT",
          "NOTIN", "IN",
          "LIKE", 
          "BETWEEN":                         infixNode  t.sval
        of "$", "NOT":                       prefixNode t.sval
        
        else:
          # TODO dot have idents: movie.
          gIdent     t.sval


    ++i

    if isNode:
      if isFirst:
        stack[^1].children.add node
      else:
        stack[^1].children[^1].children.add node

    isFirst = t.kind in {lkSep, lkIndent, lkDeIndent}
    isNode  = false

    # ignore:
    #   discard stdin.readLine

  stack[0]
  
func parseGql*(content: string): GqlNode = 
  parseGql lexGql content


when defined test_for_fns:
  echo firstLineIndentation """

    dasdks
      ds
    ads
    ad
  """
  echo firstLineIndentation """
  
    
    
  """

when isMainModule:

  const sample =   """
    #person   p
    #movie    m
    @acted_in a

    AS
      no_movies
      ()
        COUNT
        m.id

    -- *a means that include `p`s that may not have any edge `a` connected to `a` movie at all

    MATCH   ^p>-*a->m
    GROUP   p.id

    ORDER no_movies
    SORT  DESC 
    RETURN  
      {}
        "person"
        p

        "movies"
        [].
          m.title

        "no_movies"
        no_movies
  """

  let tokens = lexGql sample

  let ggg  = parseGql tokens

  print ggg
