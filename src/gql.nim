import std/[strutils, sequtils, tables, json, nre, sugar, strformat]
import ./utils

import db_connector/db_sqlite
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

  GqlKind* = enum
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
    gkBool        # true false
    gkStrLit      # "salam"

    gkNull        # :
    gkInf         # inf

    gkVar         # |var|
    gkChain       # 1-:->p

    gkTake        # select take

    gkNameSpace   # namespace
    gkDataBase    # database
    gkStructure   # structure, struct, table, object, obj
    gkRelation    # references, ref, rel, relation
    gkProcedure   # procedure, func
    gkFrom        # from
    gkLimit       # limit
    gkComment     # --

    gkIdSpecifier # @ID
    gkFieldAccess # table.field

    gkWrapper

  GqlNode* = ref object
    children*: seq[GqlNode]

    case kind*: GqlKind
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

  AskPatKind = enum
    apkNode
    apkArrow

  ArrowDir = enum
    headL2R = ">-"
    tailL2R = "->"
    headR2L = "-<"
    tailR2L = "<-"

  IdentMap = Table[string, string]

  QueryChain = seq[AskPatNode]

  AskPatNode = object
    case kind: AskPatKind

    of apkNode:
      ident: string
      negate: bool       # !
      mark: Option[char] ## special prefix

    of apkArrow:
      dir: ArrowDir

  SqlPatKind = enum
    sqkStr
    sqkCommand

  SqlPatSep = object
    case kind: SqlPatKind
    of sqkStr:
      content: string

    of sqkCommand:
      cmd: string
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


using 
  gn:          GqlNode
  imap:        IdentMap
  varResolver: string -> string


func `$`*(s: SqlQuery): string =
  s.string

func `$`(qc: QueryChain): string =
  for p in qc:
    case p.kind
    of apkNode:
      if p.negate:
        result.add '!'

      if m =? p.mark:
        result.add m

      result.add p.ident

    of apkArrow:
      result.add $p.dir


proc cmd(ind: int, line: string): string =
  line
    .match(
      re "[\".#=<>!%*+-/^$?|]+|\\d+|\\w+",
      ind,
      line.high)
    .get
    .match
    .toUpper


func parseComment    (line: string): GqlNode =
  GqlNode(
    kind: gkComment,
    sval: line.substr 2)

func parseString     (line: string): GqlNode =
  assert line[0] == '"'
  assert line[^1] == '"'
  GqlNode(
    kind: gkStrLit,
    sval: line[1 .. ^2])

func parseNumber     (line: string): GqlNode =
  GqlNode(
    kind: gkIntLit,
    ival: parseint line)

func parseIdent      (line: string): GqlNode =
  GqlNode(
    kind: gkIdent,
    sval: line)

func parseInfixOp    (line: string): GqlNode =
  GqlNode(
    kind: gkInfix,
    children: @[parseIdent line])

func parseAsk        (line: string): GqlNode =
  GqlNode(
    kind: gkAsk)

func parseTake       (line: string): GqlNode =
  GqlNode(
    kind: gkTake)

func parseVar        (line: string): GqlNode =
  GqlNode(
    kind: gkVar, 
    sval: line.strip(chars = {'|'}))

func parseFieldAccess(line: string): GqlNode =
  assert line[0] == '.'
  GqlNode(
    kind: gkFieldAccess,
    children: @[parseIdent line.substr 1])

func parseDefHeader  (line: string): GqlNode =
  assert line[0] == '#'
  let ll = splitWhitespace line.substr 1
  GqlNode(
    kind: gkDef,
    children: @[
      parseIdent ll[0],
      parseIdent ll[1],
    ])

func parseGql*(content: string): GqlNode =
  result = GqlNode(kind: gkWrapper)

  type
    Temp = tuple
      node: GqlNode
      indentLevel: int

  var
    nested: seq[Temp] = @[(result, -1)]

  func getParent(indent: Natural): GqlNode =
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
          of "ASK", "FROM":         parseAsk     lineee
          of "TAKE", "SELECT":      parseTake    lineee

          of "|":                   parseVar     lineee

          elif key[0] in '0'..'9': parseNumber lineee
          elif key[0] in 'A'..'Z': parseIdent  lineee

          else: raisee key

      parent.children.add n
      nested.add (n, ind)



func preProcessRawSql(s: string): seq[SqlPatSep] =
  let parts = s.split '|'
  for i, part in parts:
    result.add:
      if i mod 2 == 0:
        SqlPatSep(kind: sqkStr, content: part)
      else:
        let tmp = splitWhitespace strip part
        SqlPatSep(kind: sqkCommand, cmd: tmp[0], args: tmp[1..^1])

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

proc parseToml*(s: string): TomlValueRef =
  parseToml.parseString s

func parseQueryStrategies*(tv: TomlValueRef): seq[QueryStrategy] =
  tv["q"].getElems.map parseQueryStrategy


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

func askedQuery(gn): QueryChain =
  for ch in gn.children:
    case ch.kind
    of gkAsk: return parseQueryChain ch.children[0].sval
    else: discard

  raisee "ask query not found"

func selects(gn): seq[string] =
  for ch in gn.children:
    case ch.kind
    of gkTake: return ch.children.mapit it.sval
    else: discard

  raisee "ask query not found"

func resolveSqlImpl(node: GqlNode, name: string, varResolver): string {.effectsOf: varResolver.} = 
  case node.kind
  of gkInfix:       [
    resolveSqlImpl(node.children[1], name, varResolver), 
    resolveSqlImpl(node.children[0], name, varResolver), 
    resolveSqlImpl(node.children[2], name, varResolver)].join " "

  of gkPrefix:     [
    resolveSqlImpl(node.children[0], name, varResolver), 
    resolveSqlImpl(node.children[1], name, varResolver)].join " "

  of gkStrLit:   ["'", node.sval, "'"].join ""
  of gkIntLit:   $node.ival
  of gkFloatLit: $node.fval
  of gkInf:      "INF"
  of gkNull:     "NULL"
  of gkBool:     $node.bval
  of gkIdent:     node.sval

  of gkVar: varResolver node.sval

  of gkFieldAccess:
      let f = resolveSqlImpl(node.children[0], name, varResolver)
      fmt"json_extract({name}.data, '$.{f}')"

  else: 
    raisee fmt"cannot convert the node type {node.kind} to SQL condition"

func resolveSql(condNode: GqlNode, name: string, varResolver): string {.effectsOf: varResolver.} = 
  resolveSqlImpl condNode, name, varResolver

func sqlCondsOfNode(gn; imap; node: string, varResolver): string {.effectsOf: varResolver.} =
  let inode = imap[node]

  for n in gn.children:
    case n.kind
    of gkDef:
      let
        tag      = n.children[0].sval
        alias    = n.children[1].sval
        hasConds = n.children.len > 2
      
      if alias == node:
        result.add fmt"({inode}.tag == '{tag}'"
        
        if hasConds:
          result.add " AND (" & resolveSql(n.children[2], inode, varResolver) & ")"

        result.add ")"
        return

    else: discard
  raisee fmt"the node '{node}' not found in query"

func sqlCondsOfEdge(gn; imap; edge, source, target: string, varResolver): string {.effectsOf: varResolver.} =
  let
    iedge = imap[edge]
    isrc  = imap[source]
    itar  = imap[target]

  for n in gn.children:
    case n.kind
    of gkDef:
      let
        tag      = n.children[0].sval
        alias    = n.children[1].sval
        hasConds = n.children.len > 2
      
      if alias == edge:
        result.add fmt"({iedge}.tag == '{tag}' AND {iedge}.source={isrc}.id AND {iedge}.target={itar}.id"
        
        if hasConds:
          result.add fmt" AND ({resolveSql(n.children[2], iedge, varResolver)})"

        result.add ")"
        return

    else: discard
  raisee fmt"the node '{edge}' not found in query"

func resolve(sqlPat: seq[SqlPatSep], imap; gn; varResolver): string {.effectsOf: varResolver.} =
  let
    s           = gn.selects.map imap
    # a = gn.askedQuery
    revmap      = rev imap

  var acc = ""

  for i, p in sqlPat:
    acc.add:
      case p.kind
      of sqkStr:
        p.content

      of sqkCommand:
        case toUpper p.cmd
        of "SELECT_FIELDS":
          s.map(it =>
            fmt"{it}.data")
            .join ", "

        of "CHECK_NODE":
          sqlCondsOfNode(gn, imap, revmap[p.args[0]], varResolver)

        of "CHECK_EDGE":
          sqlCondsOfEdge(gn, imap,
            revmap[p.args[0]], revmap[p.args[1]], revmap[p.args[2]], varResolver)

        of "EXISTS_EDGE": 
          # TODO probably should use CHECK_EDGE
          raisee "NOT IMPLEMENED: " & p.cmd

        of "GET":
          varResolver p.args[0]

        of "SORT_CLAUSE":   ""
        of "OFFSET_CLAUSE": ""
        of "LIMIT_CLAUSE":  ""
        else: raisee "invalid gql pattern: " & $p

  acc

func toSql*(gn; queryStrategies: seq[QueryStrategy], varResolver): SqlQuery {.effectsOf: varResolver.} =
  for qs in queryStrategies:
    if identMap =? matches(gn.askedQuery, qs.pattern):
      if (gn.selects.map identMap) <= qs.selectable:
        return sql resolve(qs.sqlPattern, identMap, gn, varResolver)

  raisee "no pattern was found"


when isMainModule:
  let
    queryStrategies = parseQueryStrategies parseToml readfile "./src/qs.toml"
    parsedGql       =                      parseGql  readFile "./test/sakila/get.gql"

    mname = "ACADEMY DINOSAUR"
    ctx = %*{"mtitle": mname}

    sql = tosql(parsedGql, queryStrategies, s => $ctx[s])
    graphDB = open("graph.db", "", "", "")

  # print queryStrategies[0]
  # print parsedGql
  echo   sql
  for row in graphDB.getAllRows(sql):
    echo row[0].parseJson.pretty 4
