import std/[strutils, sequtils, tables, json, nre, tables]
import db_connector/db_sqlite
import ./utils

import pretty # for debugging
import questionable
import parsetoml


type
  GqlOperator* = enum
    goLess      # <
    goLessEq    # <=
    goEq        # =
    goNotEq     # !=
    goMoreEq    # >=
    goMore      # >
    goPlus      # +
    goMinus     # -
    goMult      # *
    goDiv       # /
    goMod       # %
    goIn        # in
    goNotIn     # notin
    goEmpty     # empty?
    goCheckNull # null?

    goAnd       # and
    goOr        # or
    goUnion     # union
    goSubtract  # subtract
    goGroup     # (a b c)

  GqlKind*     = enum
    gkDef         # #tag
    gkFieldPred   # inside def
    gkAsk         # ask [limit] [offset] query
    gkReturn      # return
    gkUpdate      # update
    gkDelete      # delete

    gkUnique      # unique

    gkTypes       # types
    gkSort        # sort

    gkInsertNode  # insert node
    gkInsertEdge  # insert edge

    gkDeleteIndex # delete index
    gkCreateIndex # create index

    gkListIndexes # list indexes

    gkInfix       # a + 2
    gkPrefix      # not good

    gkIdent       # name
    gkIntLit      # 13
    gkFloatLit    # 3.14
    gkStrLit      # "salam"
    gkChain       # 1-:->p

    gkNull        # :
    gkBool        # true false
    gkInf         # inf

    gkVar         # |var|

    gkTake        # select take

    gkNameSpace   # namespace
    gkDataBase    # database
    gkStructure   # structure, struct, table, object, obj
    gkRelation    # references, ref, rel, relation
    gkProcedure   # procedure, proc
    gkFrom        # from
    gkLimit       # limit
    gkComment     # --

    gkIdSpecifier # @ID
    gkFieldAccess # table.field

    gkWrapper

  GqlNode*     = ref object
    children*: seq[GqlNode]

    case kind*: GqlKind
    of gkIdent, gkStrLit, gkComment:
      sval*: string

    of gkIntLit:
      ival*: int

    of gkFloatLit:
      fval*: float

    else:
      discard

  AskPatKind   = enum
    apkNode
    apkArrow

  ArrowDir     = enum
    headL2R # >-
    tailL2R # ->
    headR2L # -<
    tailR2L # <-

  IdentMap     = Table[string, string]

  QueryChain   = seq[AskPatNode]

  AskPatNode   = object
    case kind: AskPatKind

    of apkNode:
      ident: string
      negate: bool  # !
      mark: Option[char] ## special prefix

    of apkArrow:
      dir: ArrowDir

  SqlPatKind    = enum
    sqkStr
    sqkCommand

  SqlPatSep     = object
    case kind: SqlPatKind
    of sqkStr:
      content: string

    of sqkCommand:
      args: seq[string]

  QueryStrategy = object
    pattern: QueryChain
    selectable: seq[string]
    sqlPattern: seq[SqlPatSep]


const notionChars = {
  '0', '1', '2', '3',
  '4', '5', '6', '7',
  '8', '9', '*', '$',
  '^'}


func `$`(s: SqlQuery): string =
  s.string


func cmd(ind: int, line: string): string =
  line
    .match(
      re "[\".#=<>!%*+-/^$?]+|\\d+|\\w+",
      ind,
      line.high)
    .get
    .match
    .toUpper


proc parseComment (line: string): GqlNode =
  GqlNode(
    kind: gkComment,
    sval: line.substr 2)

proc parseString     (line: string): GqlNode = 
  assert line[ 0] == '"' 
  assert line[^1] == '"'
  GqlNode(
    kind: gkStrLit,
    sval: line[1 .. ^2])

proc parseNumber  (line: string): GqlNode =
  GqlNode(
    kind: gkIntLit,
    ival: parseint line)

proc parseIdent   (line: string): GqlNode =
  GqlNode(
    kind: gkIdent,
    sval: line)

proc parseInfixOp (line: string): GqlNode =
  GqlNode(
    kind: gkInfix,
    children: @[parseIdent line])

proc parseAsk     (line: string): GqlNode =
  GqlNode(
    kind: gkAsk)

proc parseTake    (line: string): GqlNode =
  GqlNode(
    kind: gkTake)

proc parseFieldAccess(line: string): GqlNode =
  assert line[0] == '.'
  GqlNode(
    kind: gkFieldAccess,
    children: @[parseIdent line.substr 1])

proc parseDefHeader (line: string): GqlNode =
  assert line[0] == '#'
  let ll = splitWhitespace line.substr 1
  GqlNode(
    kind: gkDef,
    children: @[
      parseIdent ll[0],
      parseIdent ll[1],
    ])

proc parseGql (content: string): GqlNode =
  result = GqlNode(kind: gkWrapper)

  type
    Temp = tuple
      node: GqlNode
      indentLevel: int

  var
    nested: seq[Temp] = @[(result, -1)]

  proc getParent(indent: Natural): GqlNode =
    while not empty nested:
      let p = nested.last
      if p.indentLevel >= indent:
        prune nested
      else:
        return p.node

  for line in splitLines content:
    if not isEmptyOrWhitespace line:
      let
        ind = indentation line
        key = cmd(ind, line)
        lineee = strip line
        parent = getParent ind
        n =
          case key
          of "--": parseComment lineee
          # of "DATABASE":         parseDatabase    lineee
          # of "SCHEMA", "TABLE":  parseSchema      lineee
          # of "REFERENCES":       parseReferences  lineee
          # of "NAMESPACE":        parseNamespace  lineee
          # of "PROC":       parseProc  lineee
          # of "LIMIT":       parseLimit  lineee
          # of "ORDER":       parseOrder  lineee # DESC or ASC


          of ".": parseFieldAccess lineee
          of "\"": parseString lineee
          of "#": parseDefHeader lineee
          of "==", "!=",
             "<", "<=",
             ">=", ">",
             "AND", "NAND",
             "OR", "NOR",
             "EQ", "NEQ",
             "GT", "GTE",
             "LT", "LTE",
             "XOR", "IS", "ISNOT",
             "NOTIN", "IN", "HAS",
             "BETWEEN", "CONTAINS": parseInfixOp lineee
          of "ASK", "FROM": parseAsk lineee
          of "TAKE", "SELECT": parseTake lineee

          elif key[0] in '0'..'9': parseNumber lineee
          elif key[0] in 'A'..'Z': parseIdent lineee

          else: raisee key

      parent.children.add n
      nested.add (n, ind)



func preProcessRawSql(s: string): seq[SqlPatSep] =
  let parts = s.split '|'
  for i, part in parts:
    result.add:
      if i mod 2 == 0: SqlPatSep(kind: sqkStr, content: part)
      else: SqlPatSep(kind: sqkCommand, args: splitWhitespace strip part)

func parseQueryChain(patt: string): QueryChain =
  for kw in patt.findAll re"[0-9$%^*]?\w+|[-<>]{2}": # TODO do not use regex
    result.add:
      case kw
      of ">-": AskPatNode(kind: apkArrow, dir: headL2R)
      of "->": AskPatNode(kind: apkArrow, dir: tailL2R)
      of "-<": AskPatNode(kind: apkArrow, dir: headR2L)
      of "<-": AskPatNode(kind: apkArrow, dir: tailR2L)
      else:
        let (mark, negate, id) =
          case kw[0]
          of notionChars: (some kw[0], false, kw.substr 1)
          of '!': (none char, true, kw)
          else: (none char, false, kw)

        AskPatNode(
          kind: apkNode,
          ident: id,
          negate: negate,
          mark: mark)

func parseQueryStrategy(pattern, selectable, query: string): QueryStrategy =
  QueryStrategy(
    pattern: parseQueryChain pattern,
    selectable: splitWhitespace selectable,
    sqlPattern: preProcessRawSql query)

func parseQueryStrategy(tv: TomlValueRef): QueryStrategy =
  parseQueryStrategy(
           getStr tv["pattern"],
           getStr tv["selectable"],
    dedent getStr tv["query"])

proc parseToml(s: string): TomlValueRef =
  parseToml.parseString s

func parseQueryStrategies(tv: TomlValueRef): seq[QueryStrategy] =
  tv["q"].getElems.map parseQueryStrategy


func resolve(sqlPat: seq[SqlPatSep], imap: IdentMap, g: GqlNode,
    ctx: JsonNode): SqlQuery =
  discard

func matches(pattern, query: QueryChain): Option[IdentMap] =
  var temp: IdentMap

  if pattern.len == query.len:
    for i, p in pattern:
      let q = query[i]

      if p.kind == q.kind:
        case p.kind
        of apkArrow:
          if p.dir != q.dir:
            return

        of apkNode:
          if p.negate == q.negate and
             p.mark == q.mark:

            if p.ident in temp:
              if temp[p.ident] != q.ident:
                return
            else:
              temp[p.ident] = q.ident

          else:
            return

    return some temp

func askedQuery(g: GqlNode): QueryChain =
  for ch in g.children:
    case ch.kind
    of gkAsk: return parseQueryChain ch.children[0].sval
    else: discard

  raisee "ask query not found"

func selects(g: GqlNode): seq[string] =
  for ch in g.children:
    case ch.kind
    of gkTake: return ch.children.mapit it.sval
    else: discard

  raisee "ask query not found"

proc toSql(g: GqlNode, queryStrategies: seq[QueryStrategy],
    ctx: JsonNode): SqlQuery =
  for qs in queryStrategies:
    if
      identMap =? matches(qs.pattern, g.askedQuery) and
      (g.selects.map identMap) <= qs.selectable
    :
      return resolve(qs.sqlPattern, identMap, g, ctx)

  raisee "no pattern was found"


when isMainModule:
  let
    queryStrategies = parseQueryStrategies parseToml readfile "./src/qs.toml"
    parsedGql       =                      parseGql  readFile "./test/sakila/get.gql"

    mname = "ACADEMY DINOSAUR"
    ctx = %*{"mtitle": mname}

  # print queryStrategies[0]
  print parsedGql
  print tosql(parsedGql, queryStrategies, ctx)
