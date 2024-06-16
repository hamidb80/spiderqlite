import std/[strutils, sequtils, tables, json, nre, sugar, strformat]
import ./utils/[other, mat]

import db_connector/db_sqlite
import pretty
import questionable
import parsetoml


type
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

  AskPatKind = enum
    apkNode
    apkArrow

  ArrowDir = enum
    headL2R = ">-"
    tailL2R = "->"
    headR2L = "-<"
    tailR2L = "<-"

  AskPatNode = object
    case kind: AskPatKind

    of apkNode:
      node: QueryNode

    of apkArrow:
      dir: ArrowDir

  Dir = enum
    l2r
    r2l

  IdentMap = Table[string, string]

  QueryChain = seq[AskPatNode]

  # Index = Natural

  Travel[T]  = object 
    ## a>-c->b : travels from node(a) to node(b) with condition(c)
    a, c, b: T

  QueryPartKind  = enum
    qpSingle
    qpMulti

  QueryPart = object
    case kind: QueryPartKind
    of qpSingle:
      node: QueryNode
    of qpMulti:
      travel: Travel[QueryNode]

  QueryNode  = object
    ident:  string
    mode:   char   ## nothing, !, ?
    mark:   char   ## special prefix, is used to differentiate

  QueryGraph  = ref object
    nodes:    seq[QueryNode]
    iocounts: seq[IOcount]
    rels:     Mat[seq[QueryNode]]


  SqlPatKind = enum
    sqkStr
    sqkCommand

  SqlPatSep* = object
    case kind*: SqlPatKind
    of sqkStr:
      content*: string

    of sqkCommand:
      cmd*: string
      args*: seq[string]

  QueryStrategy* = ref object
    key:        string
    parameters: seq[string]
    pattern:    QueryGraph
    selectable: seq[string]
    sqlPattern: seq[SqlPatSep]

  QueryStrategies* = ref object
    collection*: seq[QueryStrategy]

  AliasLookup = Table[string, GqlNode]

  IOcount = tuple
    inward, outward: Natural

using 
  gn:              GqlNode
  imap:            IdentMap
  varResolver:     string -> string
  queryStrategies: QueryStrategies


const 
  notionChars      = {'0' .. '9', '^', '*'}
  invalidIndicator = '\0'
  notFound = -1

func `$`(p: AskPatNode): string =
  case p.kind
  of apkNode:
    result.add $p.node

  of apkArrow:
    result.add $p.dir

func `$`(qc: QueryChain): string =
  join qc
    
func `$`(qn: QueryNode): string = 
  if qn.mode != invalidIndicator:
    << qn.mode
    
  if qn.mark != invalidIndicator:
    << qn.mark

  << qn.ident

func `$`*(g: QueryGraph): string = 
  let maxNamesLen = max (g.nodes ~> len it.ident)

  << '_'.repeat maxNamesLen
  << '|'
  
  for b in g.nodes:
    << b.ident
    << ' '.repeat maxNamesLen - b.ident.len
    << '|'
  << '\n'

  
  for i, a in g.nodes:
    << a.ident
    << ' '.repeat maxNamesLen - a.ident.len
    << '|'

    for j, b in g.nodes:
      let 
        n   = g.rels[i,j].len
        s   = $n

      << s
      << ' '.repeat maxNamesLen - s.len
      << '|'

    << '\n'  

  less result


func cmd(ind: int, line: string): string =
  line
    .match(
      re "#|@|[$\"|.=<>!%*+-/^$?(){}\\[\\]]+|\\d+|\\w+",
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

func isString(line: string): bool = 
  line[0]  == '"' and
  line[^1] == '"'

func parseString     (line: string): GqlNode =
  if isString line:
    GqlNode(
      kind: gkStrLit,
      sval: line[1 .. ^2])
  else:
    raisee "invalid string format: " & line

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
  let 
    dk = 
      case line[0]
      of '#': defNode
      of '@': defEdge
      else:
        raisee "invalid def header start character: " & line[0]

    ll = splitWhitespace line.substr 1
  
  GqlNode(
    kind: gkDef,
    defKind: dk,
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
        less nested
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

          of "ASK", "MATCH":                   gNode gkAsk
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
             "BETWEEN", "CONTAINS":            parseInfix       lineee

          of "$", "NOT":                       parsePrefix      lineee          
          of ".":                              parseFieldAccess lineee
          of "\"", "\"\"":                     parseString      lineee
          of "#", "@":                         parseDefHeader   lineee

          of "|":                              parseVar         lineee
          elif key[0] in '0'..'9':             parseNumber      lineee
          elif key[0] in 'A'..'Z':             parseIdent       lineee

          elif parent.kind == gkAsk:           parseIdent       lineee

          else: 
            raisee key

      parent.children.add n
      nested.add (n, ind)
  debugEcho "pARSREDL:ASDLKJS DSALJK DLASKjD LKASJD"

func `$`(gn): string = 
  raisee "TODO"


func infoLevel(n: QueryNode): int =
  if n.mark != invalidIndicator:
    inc result
  
  if n.mode != invalidIndicator:
    inc result


func nodeIndex(g: var QueryGraph, node: QueryNode): int = 
  let i = g.nodes.findit it.ident == node.ident
  if  i == notFound:
    g.nodes   .add  node
    g.iocounts.more 

    g.rels.addRow    @[]
    g.rels.addColumn @[]

    g.nodes.high

  else:
    # e.g. replace ^m with m
    if g.nodes[i].infoLevel < node.infoLevel:
      g.nodes[i] = node
    i

func addNode(g: var QueryGraph, node: QueryNode) = 
  discard g.nodeIndex node

func addEdge(g: var QueryGraph, a, b, c: QueryNode) = 
  let 
    i = g.nodeIndex a
    j = g.nodeIndex b

  add g.rels[i, j], c
  inc g.iocounts[i].outward
  inc g.iocounts[j].inward 


func addConn(g: var QueryGraph, a, b, c: QueryNode) = 
  g.addNode a
  g.addNode b
  g.addEdge a, b, c

func preProcessRawSql*(s: string): seq[SqlPatSep] =
  let parts = s.split '|'
  for i, part in parts:
    result.add:
      if i mod 2 == 0:
        SqlPatSep(kind: sqkStr, content: part)
      else:
        let tmp = splitWhitespace strip part
        SqlPatSep(kind: sqkCommand, cmd: tmp[0], args: rest tmp)

func toArrow(d: ArrowDir): AskPatNode = 
  AskPatNode(kind: apkArrow, dir: d)

func parseQueryNode(s: string): QueryNode = 
  var i = 0
  
  if s[i] in {'!', '?'}:
    result.mode = s[i]
    inc i

  if s[i] in notionChars:
    result.mark = s[i]
    inc i

  while i < s.len:
    result.ident.add s[i]
    inc i

func lexQueryImpl(str: string, i: var int): AskPatNode = 
  let m = str.find(re"[-<>]{2}|[?!]?[0-9^]?\w+", i).get.match
  i.inc m.len
  case m
  of ">-": toArrow headL2R
  of "->": toArrow tailL2R
  of "-<": toArrow headR2L
  of "<-": toArrow tailR2L
  else: AskPatNode(kind: apkNode, node: parseQueryNode m)

func lexQuery(str: string): QueryChain = 
  var i = 0
  while i < str.len:
    result.add lexQueryImpl(str, i)

converter conv(ad: ArrowDir): Dir = 
  case ad
  of headL2R, tailL2R: l2r
  of headR2L, tailR2L: r2l

func rev(t: Travel): Travel = 
  Travel(a: t.b, b: t.a, c: t.c)

func sepQuery(qc: QueryChain): seq[QueryPart] = 
  # a>-c1->b<-c2-<d :: b<-c2-<d, a>-c1->b
  # a>-c1->b        :: b<-c2-<d
  # a               :: a

  let sz = qc.len

  # template firstp: untyped {.dirty.} =
  #   i == 0


  if   sz == 1:
    << QueryPart(kind: qpSingle, node: qc[0].node)

  elif oddp sz:
    var dir: Dir
    # var qp: QueryPart
    var tr: Travel[QueryNode]

    for i, t in qc:
      case i mod 4
      of 0: # node
        if i != 0:
          tr.b = t.node

          << QueryPart(
            kind: qpMulti, 
            travel: iff(dir == l2r, tr, rev tr)) 
                  
        tr.a = t.node
        
      of 1: # arrow
        dir = t.dir

      of 2: # edge
        tr.c = t.node

      of 3: # arrow
        if dir != t.dir:
          raisee "edge direction is not consistent, expected same direction as " & $dir & " but got "  & $t.dir


  else:
    raisee "invalid query length: " & $sz


  for i, en in qc:
    case i mod 5
    of 0: discard
    of 1 .. 4: discard

func parseQueryGraph(patts: seq[string]): QueryGraph =
  result = QueryGraph()
  
  for p in patts:
    if not isEmptyOrWhitespace p:
      for t in sepQuery lexQuery p:
        case t.kind
        of qpSingle: result.addNode t.node
        of qpMulti:  result.addConn t.travel.a, t.travel.b, t.travel.c
  
func parseQueryStrategy(key, params, pattern, selectable, query: string): QueryStrategy =
  QueryStrategy(
    key:        key,
    parameters: splitWhitespace params,
    pattern:    parseQueryGraph  splitLines pattern,
    selectable: splitWhitespace             selectable,
    sqlPattern: preProcessRawSql            query)

func parseQueryStrategy(tv: TomlValueRef): QueryStrategy =
  parseQueryStrategy(
           getStr tv["key"],
           getStr tv["parameters"],
    dedent getStr tv["pattern"],
           getStr tv["selectable"],
    dedent getStr tv["sql"])

proc parseToml*(s: string): TomlValueRef =
  ignore:
    parseToml.parseString s

func parseQueryStrategies*(tv: TomlValueRef): QueryStrategies =
  QueryStrategies(
    collection: tv["queries"].getElems.map parseQueryStrategy)


func initIdentMap: IdentMap = 
  result["."] = "."

func identMapFromCandidates(p, q: QueryGraph, candidates: seq[int]): IdentMap = 
  result = initIdentMap()

  for i, j in candidates:
    result[p.nodes[i].ident] = q.nodes[j].ident

func similar(n, m: QueryNode): bool = 
  n.mark == m.mark and
  n.mode == m.mode


func update(a: var IdentMap, b: IdentMap) = 
  for k, v in b:
    a[k] = v

func evaluateCandidate(p, q: QueryGraph, candidates: seq[int]): Option[IdentMap] = 
  

  # check node's meta
  for i, j in candidates:
    let 
      n = p.nodes[i]
      m = q.nodes[j]
    
    if not n.similar m:
      return 

  # check rels
  let 
    h = p.rels.height
    w = p.rels.width

  var acc = initIdentMap()
  
  for y in times h:
    for x in times w:
      let 
        i  = candidates[y]
        j  = candidates[x]

      var
        n = 0
        m = 0
        r1 = p.rels[y,x]
        r2 = q.rels[i,j]

      if r1.len != r2.len:
        return
    
      while n < r1.len:
        var found = false
        
        while m < r2.len:
          if r1[0] .similar r2[m]:
            acc[r1[0].ident] = r2[m].ident
            del r1, 0
            del r2, m
            m = min(r2.high, m)
            found = true
            break
          else:
            inc m

        if not found:
          return

  return some acc

func hasDuplicated(imapIndex: seq[int]): bool = 
  var chosen = false *< imapIndex.len

  for i, j in imapIndex:
    if chosen[j]:
      return true
    else:
      chosen[j] = true
  
  false

func select[T](c: seq[seq[T]], s: seq[int]): seq[T] = 
  for i, x in s:
    result.add c[i][x]

iterator chooseCandidates(candidates: seq[seq[int]]): seq[int] = 
  var 
    size         = len candidates
    indexLimits  = candidates ~> it.len - 1
    indexes      = 0 *< size
    cont         = true
  
  while cont:
    let cand = candidates.select indexes
    
    if not hasDuplicated cand:
      yield cand

    # inc
    for i in 0..size:
      if i == size:
        cont = false

      elif indexes[i] < indexLimits[i]:
        inc indexes[i]
        break
      
      else:
        indexes[i] = 0

func matchImpl(p, q: QueryGraph): Option[IdentMap] =
  var candidates: seq[seq[int]]

  for i in times p.nodes.len:
    candidates.add @[]

    for j in times q.nodes.len:
      if p.iocounts[i] == q.iocounts[j]:
        candidates[^1].add j

  if candidates.anyit it.len == 0:
    return

  for c in chooseCandidates candidates:
    if edgeIdMap =? evaluateCandidate(p, q, c):
      var acc = identMapFromCandidates(p, q, c)
      acc.update edgeIdmap
      return some acc

func canMatch(p, q: QueryGraph): bool = 
  p.nodes.len == q.nodes.len

func matches(p, q: QueryGraph): Option[IdentMap] =
  if p.canMatch q:
    if =??matchImpl(p, q): 
      return it


func fieldAccessOf(s: string): string {.inline.} = 
  if s == "": ""      # anonymous
  else:       s & '.' # named

func sqlJsonNodeExpr*(s: string): string = 
  let fi = fieldAccessOf s
  "json_object("                &
  " 'id',  "      & fi & "id  " &
  ",'tag', "      & fi & "tag " &
  ",'doc', json(" & fi & "doc)" &
  ")"

func sqlJsonEdgeExpr*(s: string): string = 
  let fi = fieldAccessOf s
  "json_object("                   &
  " 'id',  "      & fi & "id  "    &
  ",'tag', "      & fi & "tag "    &
  ",'doc', json(" & fi & "doc)"    &
  ",'source', "   & fi & "source " &
  ",'target', "   & fi & "target " &
  ")"

func resolveSql(node: GqlNode, relIdents: seq[string], mode: string, name: string, varResolver): string {.effectsOf: varResolver.} = 
  case node.kind
  of gkInfix:       [
    resolveSql(node.children[1], relIdents, mode, name, varResolver), 
    resolveSql(node.children[0], relIdents, mode, name, varResolver), 
    resolveSql(node.children[2], relIdents, mode, name, varResolver)].join " "

  of gkPrefix:     
    let s = node.children[0].sval
    case s
    of  "$": 
      "'' || " & 
      resolveSql(node.children[1], relIdents, mode, name, varResolver)

    else: 
      resolveSql(node.children[0], relIdents, mode, name, varResolver) &
      " " & 
      resolveSql(node.children[1], relIdents, mode, name, varResolver)

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
    of 0: 
      if mode == "select": 
        if s in relIdents: sqlJsonEdgeExpr s
        else:              sqlJsonNodeExpr s
      else: s
    of 1: # field acceses
      resolveSql(node.children[0], relIdents, mode, s, varResolver)
    else:
      raisee "invalid ident with children count of: " & $node.children.len
  
  of gkCall: 
      node.children[0].sval & 
      '(' & 
      node.children.rest.mapit(resolveSql(it, relIdents, mode, name, varResolver)).join(", ") &
      ')'

  of gkFieldAccess:
      let f = resolveSql(node.children[0], relIdents, "normal", name, varResolver)
      case f
      of "id", "tag": fmt"{name}.{f}"
      of "doc":       fmt"json({name}.{f})"
      else:           fmt"json_extract({name}.doc, '$.{f}')"

  of gkCase:
    "CASE " & 
    node.children.mapIt(resolveSql(it, relIdents, mode, name, varResolver)).join(" ") & 
    " END"

  of gkWhen:
    "WHEN " & 
    resolveSql(node.children[0], relIdents, mode, name, varResolver) & 
    " THEN " &
    resolveSql(node.children[1], relIdents, mode, name, varResolver)

  of gkElse:
    "ELSE " & 
    resolveSql(node.children[0], relIdents, mode, name, varResolver)

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
          result.add " AND (" & resolveSql(n.children[2], @[], "normal", inode, varResolver) & ")"

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
        var acc = @[fmt"{iedge}.tag == '{tag}'"]

        if isrc != ".":
          acc.add fmt"{iedge}.source={isrc}.id"

        if itar != ".":
          acc.add fmt"{iedge}.target={itar}.id"
        
        if hasConds:
          acc.add fmt"""({resolveSql(n.children[2], @[], "", iedge, varResolver)})"""

        result.add "("
        result.add acc.join " AND "
        result.add ")"
        return

    else: discard
  raisee fmt"the node '{edge}' not found in query"


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

func findNode(gn; kind: GqlKind): Option[GqlNode] = 
  for ch in gn.children:
    if ch.kind == kind: 
      return some ch

func askedQuery(gn): QueryGraph =
  let n = get gn.findNode gkAsk
  parseQueryGraph n.children.mapIt it.sval

func getTake(gn): GqlNode =
  get:
    findNode gn, gkTake

func getGroup(gn): Option[GqlNode] = 
  findNode gn, gkGroupBy


func toSqlSelectImpl(gn; relsIdent: seq[string]): string = 
  resolveSql gn, relsIdent, "select", "???", s => "!!!"

func toSqlSelect(take: GqlNode, relsIdent: seq[string], imap): string = 
  deepIdentReplace take, imap
  let mappedRels = relsIdent.map imap
  take
    .children
    .mapit(toSqlSelectImpl(it, mappedRels))
    .join ", "

func getRels(gn): seq[string] = 
  for ch in gn.children:
    if ch.kind == gkDef:
      if ch.defkind == defEdge:
        result.add ch.children[1].sval

  debugEcho result


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
          resolve(
            @[
              SqlPatSep(kind: sqkStr, content: fmt"EXISTS ( SELECT 1 FROM edges {p.args[0]} WHERE "),
              SqlPatSep(kind: sqkCommand, cmd: "CHECK_EDGE", args: p.args),
              SqlPatSep(kind: sqkStr, content: " )")],
            imap, 
            gn,
            varResolver
          )

        of "GET":
          varResolver p.args[0]


        of "SELECT_FIELDS":
          toSqlSelect takes, gn.getRels , imap

        of "GROUP_STATEMENT":  
          if g =? gn.getGroup:
            deepIdentReplace g, imap

            let temp = 
              g
              .children
              .mapIt(resolveSql(it, @[], "???", "", s => "!!!"))
              .join ", "
            
            "GROUP BY " & temp

          else: ""

        of "HAVING_STATEMENT": 
          if g =? gn.findNode gkHaving:
            deepIdentReplace g, imap

            let temp = 
              g
              .children[0]
              .resolveSql(@[], "???", "", s => "!!!")
            
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
              var temp = ch.resolveSql(@[], "???", "", s => "!!!")
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

func prepareGQuery(gn) = 
  replaceAliases gn

func findCorrespondingPattern(gn; queryStrategies): tuple[qs: QueryStrategy, imap: IdentMap] = 
  for qs in queryStrategies.collection:
    if identMap =? matches(gn.askedQuery, qs.pattern):
      if (gn.getTake.selects.map identMap) <= qs.selectable:
        return (qs, identMap)
        
  raisee "no pattern was found"

func toSqlImpl(gn; qs: QueryStrategy, imap; varResolver): SqlQuery {.effectsOf: varResolver.} =
  sql resolve(qs.sqlPattern, imap, gn, varResolver)

func toSql*(gn; queryStrategies; varResolver): SqlQuery {.effectsOf: varResolver.} = 
  prepareGQuery gn
  let p = findCorrespondingPattern(gn, queryStrategies)
  toSqlImpl gn, p.qs, p.imap, varResolver


func parseTag*(s: string): string = 
  if s.len == 0:           raisee "empty tag"
  elif s[0] in {'#', '@'}: s.substr 1
  else:                    s

# TODO add named queries
# TODO some gql grammers can be inline like PARAMTERES a b c 
# TODO faster parser
# TODO options for all routes: include-sql,
# TODO add guard