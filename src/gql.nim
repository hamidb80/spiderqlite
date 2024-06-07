import std/[strutils, sequtils, tables, json, nre, sugar, strformat]
import ./utils

import db_connector/db_sqlite
import pretty
import questionable
import parsetoml

type
  GqlOperator* = enum
    goConcat    # ||

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

    gkGroupBy     # GROUP BY
    gkTake        # select take
    gkFrom        # from
    gkHaving      # HAVING
    gkOrderBy     # ORDER BY
    gkLimit       # LIMIT
    gkOffset      # OFFSET
    gkAlias       # AS; named expressions
    gkCall        # count(a)

    gkNameSpace   # namespace
    gkDataBase    # database
    gkTable       # table
    gkRelation    # references, ref, rel, relation
    gkProcedure   # procedure, func
    
    gkComment     # --

    gkFieldAccess # .field

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

  AliasLookup = Table[string, GqlNode]

using 
  gn:          GqlNode
  imap:        IdentMap
  varResolver: string -> string


const notionChars = {
  '0', '1', '2', '3',
  '4', '5', '6', '7',
  '8', '9', '*', '$',
  '^'}

func `$`(qc: QueryChain): string {.used.} =
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


func cmd(ind: int, line: string): string =
  line
    .match(
      re "[$\"|.#=<>!%*+-/^$?(){}\\[\\]]+|\\d+|\\w+",
      ind,
      line.high)
    .get
    .match
    .toUpperAscii


func gNode(k: GqlKind): GqlNode =
  GqlNode(kind: k)

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
  try:
    GqlNode(
      kind: gkIntLit,
      ival: parseint line)
  except ValueError:
    GqlNode(
      kind: gkFloatLit,
      fval: parseFloat line)

func parseIdent      (line: string): GqlNode =
  GqlNode(
    kind: gkIdent,
    sval: line)

func parseInfix      (line: string): GqlNode =
  GqlNode(
    kind: gkInfix,
    children: @[parseIdent line])

func parsePrefix     (line: string): GqlNode =
  GqlNode(
    kind: gkPrefix,
    children: @[parseIdent line])

func parseCallToJson           (): GqlNode =
  GqlNode(
    kind: gkCall, 
    children: @[
      GqlNode(kind: gkIdent, sval: "json")])

func parseCallToJsonObject     (): GqlNode =
  GqlNode(
    kind: gkCall, 
    children: @[
      GqlNode(kind: gkIdent, sval: "json_object")])

func parseCallToJsonObjectGroup(): GqlNode =
  GqlNode(
    kind: gkCall, 
    children: @[
      GqlNode(kind: gkIdent, sval: "json_group_object")])

func parseCallToJsonArray      (): GqlNode =
  GqlNode(
    kind: gkCall, 
    children: @[
      GqlNode(kind: gkIdent, sval: "json_array")])

func parseCallToJsonArrayGroup (): GqlNode =
  GqlNode(
    kind: gkCall, 
    children: @[
      GqlNode(kind: gkIdent, sval: "json_group_array")])


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
        ind    = indentation line
        key    = cmd(ind, line)
        lineee = strip line
        parent = getParent ind
        n      =
          case key
          of "--":                             parseComment lineee

          of "DATABASE":                       gNode gkDataBase
          of "SCHEMA", "TABLE":                gNode gkTable
          of "REFERENCES":                     gNode gkRelation
          of "NAMESPACE":                      gNode gkNameSpace
          of "PROC":                           gNode gkProcedure

          of "ASK", "FROM", "MATCH":           gNode gkAsk
          of "TAKE", "SELECT", "RETURN":       gNode gkTake

          of "GROUP":                          gNode gkGroupBy
          of "ORDER":                          gNode gkOrderBy
          of "SORT":                           gNode gkSort
          of "HAVING":                         gNode gkHaving
          of "LIMIT":                          gNode gkLimit
          of "OFFSET":                         gNode gkOffset
          of "AS":                             gNode gkAlias

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
             "EQ", "NEQ",
             "GT", "GTE",
             "LT", "LTE",
             "XOR", "IS", "ISNOT",
             "NOTIN", "IN", "HAS",
             "BETWEEN", "CONTAINS":            parseInfix lineee

          of "$", "NOT":                       parsePrefix      lineee          
          of ".":                              parseFieldAccess lineee
          of "\"", "\"\"":                     parseString      lineee
          of "#":                              parseDefHeader   lineee

          of "|":                              parseVar         lineee
          elif key[0] in '0'..'9':             parseNumber      lineee
          elif key[0] in 'A'..'Z':             parseIdent       lineee

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
        SqlPatSep(kind: sqkCommand, cmd: tmp[0], args: rest tmp)

func parseQueryChain(patt: string): QueryChain =
  for kw in patt.findAll re"!?[0-9$%^*]?[\w.]+|[-<>]{2}": # TODO do not use regex
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
          else:   (none char, false, kw)

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

func resolveSql(node: GqlNode, name: string, varResolver): string {.effectsOf: varResolver.} = 
  case node.kind
  of gkInfix:       [
    resolveSql(node.children[1], name, varResolver), 
    resolveSql(node.children[0], name, varResolver), 
    resolveSql(node.children[2], name, varResolver)].join " "

  of gkPrefix:     
    let s = node.children[0].sval
    case s
    of  "$": [
      "\"\" || ",
      resolveSql(node.children[1], name, varResolver)].join 
    else   : [
      resolveSql(node.children[0], name, varResolver), 
      resolveSql(node.children[1], name, varResolver)].join " "

  of gkStrLit:   ["'", node.sval, "'"].join "" #FIXME SQL injection
  of gkIntLit:   $node.ival
  of gkFloatLit: $node.fval
  of gkInf:      "INF"
  of gkNull:     "NULL"
  of gkBool:     $node.bval

  of gkVar:      varResolver node.sval

  of gkIdent:     
    let s = node.sval
    case node.children.len
    of 0: s
    else: resolveSql(node.children[0], s, varResolver)
  
  of gkCall: 
      node.children[0].sval & 
      '(' & 
      node.children.rest.mapit(resolveSql(it, name, varResolver)).join(", ") &
      ')'

  of gkFieldAccess:
      let f = resolveSql(node.children[0], name, varResolver)
      case f
      of "id", "tag", "doc": fmt"{name}.{f}"
      else:                  fmt"json_extract({name}.doc, '$.{f}')"

  of gkCase:
    "CASE " & 
    node.children.mapIt(resolveSql(it, name, varResolver)).join(" ") & 
    " END"

  of gkWhen:
    "WHEN " & 
    resolveSql(node.children[0], name, varResolver) & 
    " THEN " &
    resolveSql(node.children[1], name, varResolver)

  of gkElse:
    "ELSE " & 
    resolveSql(node.children[0], name, varResolver)

  else: 
    raisee fmt"cannot convert the node type {node.kind} to SQL code"

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

func sqlJsonExpr(s: string): string = 
  """ ('{ "id"  :' || """ & s & """.id  ||     """ &
  """  ', "tag" :"'|| """ & s & """.tag ||     """ &
  """ '", "doc":'  || """ & s & """.doc || '}')"""

func findIdents(gn; result: var seq[string]) =
  case gn.kind
  of gkIdent:
    result.add gn.sval
  
  of gkCall, gkInfix, gkPrefix:
    for ch in rest gn.children:
      findIdents ch, result

  else:
    for a in gn.children:
      findIdents a, result
  
func selects(gn): seq[string] = 
  findIdents gn, result

func deepIdentReplace(gn; imap) = 
  case gn.kind
  of gkIdent: 
    gn.sval = imap[gn.sval]
  
  of gkCall, gkInfix, gkPrefix:
    for ch in rest gn.children:
      deepIdentReplace ch, imap

  of gkWrapper, gkTake, gkGroupBy, gkHaving, gkOrderBy, gkCase, gkElse, gkWhen:
    for ch in gn.children:
      deepIdentReplace ch, imap

  else:
    discard
  
  
func toSqlSelectImpl(gn): string = 
  if gn.kind == gkIdent and gn.children.len == 0: 
    sqlJsonExpr gn.sval
  else:       
    resolveSql gn, "???", s => "!!!"

func toSqlSelect(take: GqlNode, imap): string = 
  deepIdentReplace take, imap
  take
    .children
    .map(toSqlSelectImpl)
    .join ", "


func findNode(gn; kind: GqlKind): Option[GqlNode] = 
  for ch in gn.children:
    if ch.kind == kind: 
      return some ch

func getTake(gn): GqlNode =
  get:
    findNode gn, gkTake

func getGroup(gn): Option[GqlNode] = 
  findNode gn, gkGroupBy



func resolve(sqlPat: seq[SqlPatSep], imap; gn; varResolver): string {.effectsOf: varResolver.} =
  let
    takes       = gn.getTake
    revmap      = rev imap

  for i, p in sqlPat:
    result.add:
      case p.kind
      of sqkStr:
        p.content

      of sqkCommand:
        case toUpperAscii p.cmd         
        of "CHECK_NODE":
          sqlCondsOfNode(gn, imap, revmap[p.args[0]], varResolver)

        of "CHECK_EDGE":
          sqlCondsOfEdge(gn, imap, revmap[p.args[0]], revmap[p.args[1]], revmap[p.args[2]], varResolver)

        of "EXISTS_EDGE": 
          # TODO probably should use CHECK_EDGE
          raisee "NOT IMPLEMENED: " & p.cmd


        of "GET":
          varResolver p.args[0]


        of "SELECT_FIELDS":
          toSqlSelect takes, imap

        of "GROUP_STATEMENT":  
          if g =? gn.getGroup:
            deepIdentReplace g, imap

            let temp = 
              g
              .children
              .mapIt(it.resolveSql("???", s => "!!!"))
              .join ", "
            
            "GROUP BY " & temp

          else: ""

        of "HAVING_STATEMENT": 
          if g =? gn.findNode gkHaving:
            deepIdentReplace g, imap

            let temp = 
              g
              .children[0]
              .resolveSql("???", s => "!!!")
            
            "HAVING " & temp

          else: ""

        of "ORDER_STATEMENT":   
          if g =? gn.findNode gkOrderBy:
            deepIdentReplace g, imap

            var acc: seq[string]
            let s = 
              if ss =? gn.findNode gkSort:
                some ss.children.mapit it.sval
              else:
                none seq[string]
            

            for i, ch in g.children:
              var temp = ch.resolveSql("???", s => "!!!")
              if issome s:
                temp.add ' '
                temp.add s.get[i]
              acc.add temp
            
            "ORDER BY " & acc.join ", "

          else: ""

        of "LIMIT_STATEMENT":  
          if g =? gn.findNode gkLimit:
            "LIMIT " & $g.children[0].ival
          else:
            ""

        of "OFFSET_STATEMENT":  
          if g =? gn.findNode gkOffset:
            "OFFSET " & $g.children[0].ival
          else:
            ""


        else: 
          raisee "invalid gql pattern: " & $p


func replaceDeepImpl(father: GqlNode, index: int, gn; lookup: AliasLookup) = 
  case gn.kind
  of gkIdent: 
    let id = gn.sval
    if  id in lookup:
      father.children[index] = deepCopy lookup[id]

  of gkAlias: # replace inside of AS block
    for i in countup(1, gn.children.high, 2):
      replaceDeepImpl gn, i, gn.children[i], lookup

  else:
    for i, ch in gn.children:
      replaceDeepImpl gn, i, ch, lookup

func replaceDeep(gn; lookup: AliasLookup) = 
  replaceDeepImpl gn, 0, gn, lookup

func replLookup(gn): AliasLookup = 
  assert gn.kind == gkAlias
  
  for i in countup(0, gn.children.high, 2):
    let ch = gn.children[i]
    assert ch.kind == gkIdent
    result[ch.sval] = gn.children[i+1]

func replaceAliases(gn) = 
  if gAlias =? gn.findNode gkAlias:
    replaceDeep gn, replLookup gAlias

func toSql*(gn; queryStrategies: seq[QueryStrategy], varResolver): SqlQuery {.effectsOf: varResolver.} =
  replaceAliases gn

  for qs in queryStrategies:
    if identMap =? matches(gn.askedQuery, qs.pattern):
      if (gn.getTake.selects.map identMap) <= qs.selectable:
        result = sql resolve(qs.sqlPattern, identMap, gn, varResolver)
        return

  raisee "no pattern was found"


when isMainModule:
  let
    queryStrategies = parseQueryStrategies parseToml readfile "./src/qs.toml"
    parsedGql       =                      parseGql  readFile "./test/sakila/get_agg.gql"
    # parsedGql       =                      parseGql  readFile "./test/sakila/get.gql"
    # parsedGql       =                      parseGql  readFile "./test/sakila/simple1.gql"

    ctx = %*{"mtitle": "ZORRO ARK"}
    graphDB = open("graph.db", "", "", "")
    sql     = toSql(parsedGql, queryStrategies, s => $ctx[s])

  echo   sql
  # print  parsedGql

  for row in graphDB.getAllRows sql:
    for cell in row:
      stdout.write  cell.parseJson.pretty 4
      stdout.write ", "
    stdout.write "\n"
