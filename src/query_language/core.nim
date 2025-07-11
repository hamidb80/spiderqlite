import std/[strutils, sequtils, tables, json, sugar, strformat, options]

import db_connector/db_sqlite
import pretty
import questionable
import parsetoml

import ./parser
import ../utils/[other, mat]



const 
  nodesTable* = "Nodes"
  edgesTable* = "Edges"

  idCol*      = "__id"
  tagCol*     = "__tag"
  docCol*     = "__doc"
  sourceCol*  = "__head"
  targetCol*  = "__tail"

  emptyDoc*   = "{}"



type
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

  QueryNode    = object
    ident:  string
    mode:   char   ## nothing, !, ?, *
    mark:   char   ## special prefix, is used to differentiate

  QueryGraph  = ref object
    when defined debug:
      rawpattern:  seq[string]

    nodes:    seq[QueryNode]
    iocounts: seq[IOcount]
    rels:     Mat[seq[QueryNode]]


  SqlPatKind* = enum
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
    # TODO add fallback -- like if didn't match with any of ^a>-c->b, a>-^c->b, a>-c->^b, if saw a>-c->b, then fallback to a>-^c->b
    key:        string
    parameters: seq[string]
    pattern:    QueryGraph
    selectable: seq[string]
    edges:      seq[string]
    sqlPattern: seq[SqlPatSep]

  QueryStrategies* = ref object
    collection*: seq[QueryStrategy]
    table*     : Table[string, QueryStrategy]

  AliasLookup = Table[string, SpqlNode]

  IOcount = tuple
    inward, outward: Natural

  KindOfQuery = enum
    byPattern
    byKey

type
  Entity* = enum
    nodes = nodesTable
    edges = edgesTable


using 
  gn:              SpqlNode
  imap:            IdentMap
  varResolver:     string -> string
  queryStrategies: QueryStrategies


const 
  modeChars        = {'!', '?', '*'}
  markChars        = {'0' .. '9', '^', '$', '+'}
  invalidIndicator = '\0'


func `$`(p: AskPatNode): string =
  case p.kind
  of apkNode:
    if p.node.mode != invalidIndicator:
      << p.node.mode

    if p.node.mark != invalidIndicator:
      << p.node.mark

    << p.node.ident

  of apkArrow:
    << $p.dir

func `$`(qc: QueryChain): string =
  join qc
    
func `$`*(qn: QueryNode): string = 
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

func `$`*(gn): string = 
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
        if part == "":  # to support string concatinator ||
          SqlPatSep(kind: sqkStr, content: "||")
        else:
          let tmp = splitWhitespace strip part
          SqlPatSep(kind: sqkCommand, cmd: tmp[0], args: rest tmp)

func toArrow(d: ArrowDir): AskPatNode = 
  AskPatNode(kind: apkArrow, dir: d)

func parseQueryNode(s: string): QueryNode = 
  var i = 0
  
  if s[i] in modeChars:
    result.mode = s[i]
    inc i

  if s[i] in markChars:
    result.mark = s[i]
    inc i

  while i < s.len:
    add result.ident, s[i]
    inc i

func discriminate(str: string, specials: set[char]): seq[string] = 
  var isSpecial = false
  add result, ""

  for ch in str:
    if ch in specials:
      if not isSpecial:
        isSpecial = true
        add result, ""

    else:
      if isSpecial:
        isSpecial = false
        add result, ""

    result[^1].add ch

func lexQueryImpl(str: string): AskPatNode = 
  case str
  of ">-": toArrow headL2R
  of "->": toArrow tailL2R
  of "-<": toArrow headR2L
  of "<-": toArrow tailR2L
  else: AskPatNode(kind: apkNode, node: parseQueryNode str)

func lexQuery(str: string): QueryChain = 
  discriminate(str, {'<', '>', '-'}).map lexQueryImpl

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
          raisee "invalid"

  else:
    raisee "invalid query length: " & $sz & "query chain was: " & $qc

  # for i, en in qc:
  #   case i mod 5
  #   of 0: discard
  #   of 1 .. 4: discard

func parseQueryGraph(patts: seq[string]): QueryGraph =
  result = QueryGraph()

  when defined debug:
    result.rawpattern = patts
    
  
  for p in patts:
    if not isEmptyOrWhitespace p:
      for t in sepQuery lexQuery p:
        case t.kind
        of qpSingle: result.addNode t.node
        of qpMulti:  result.addConn t.travel.a, t.travel.b, t.travel.c

func parseQueryStrategy(key, params, pattern, selectable, edges, query: string): QueryStrategy =
  QueryStrategy(
    key:        key,
    parameters: splitWhitespace params,
    pattern:    parseQueryGraph  splitLines pattern,
    selectable: splitWhitespace             selectable,
    edges:      splitWhitespace             edges,
    sqlPattern: preProcessRawSql            query)

func parseQueryStrategy(tv: TomlValueRef): QueryStrategy =
  parseQueryStrategy(
           getStr tv["key"],
           getStr tv["parameters"],
    dedent getStr tv["pattern"],
           getStr tv["selectable"],
           getStr tv["edges"],
    dedent getStr tv["sql"])

proc parseToml*(s: string): TomlValueRef =
  ignore:
    parseToml.parseString s

func parseQueryStrategies*(elems: seq[TomlValueRef]): QueryStrategies =
  let col = elems.map parseQueryStrategy
  QueryStrategies(
    collection: col,
    table     : makeTabBy(col, it.key, it, true)
  )


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
  
  for y in 0..<h:
    for x in 0..<w:
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
    add result, c[i][x]

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

  for i in 0..<p.nodes.len:
    add candidates, @[]

    for j in 0..<q.nodes.len:
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
  fmt"""
  json_object(                   
     '{idCol}',       {fi}{idCol}    
    ,'{tagCol}',      {fi}{tagCol}   
    ,'{docCol}', json({fi}{docCol})  
  )"""

func sqlJsonEdgeExpr*(s: string): string = 
  let fi = fieldAccessOf s
  fmt"""
  json_object(                   
     '{idCol}',          {fi}{idCol}    
    ,'{tagCol}',         {fi}{tagCol}   
    ,'{docCol}',    json({fi}{docCol})  
    ,'{sourceCol}',      {fi}{sourceCol} 
    ,'{targetCol}',      {fi}{targetCol} 
  )"""

func resolveSql(node: SpqlNode, relIdents: seq[string], mode: string, name: string, varResolver): string {.effectsOf: varResolver.} = 
  case node.kind
  of gkInfix:       [
    resolveSql(node.children[0], relIdents, mode, name, varResolver), 
    node.sval,
    resolveSql(node.children[1], relIdents, mode, name, varResolver)].join " "

  of gkPrefix:     
    case node.sval
    of  "$": 
      "'' || " & 
      resolveSql(node.children[0], relIdents, mode, name, varResolver)

    else: 
      resolveSql(node.children[0], relIdents, mode, name, varResolver) &
      " " & 
      resolveSql(node.children[1], relIdents, mode, name, varResolver)

  of gkStrLit:   dbQuote node.sval
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
      node.sval & 
      '(' & 
      node.children.mapit(resolveSql(it, relIdents, mode, name, varResolver)).join(", ") &
      ')'

  of gkFieldAccess:
      let f = resolveSql(node.children[0], relIdents, "normal", name, varResolver)
      case f
      of idCol, tagCol: fmt"{name}.{f}"
      of docCol:        fmt"json({name}.{f})"
      else:             fmt"json_extract({name}.{docCol}, '$.{f}')"

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


func defInfo(n: SpqlNode): tuple[tag: string, aliases: seq[string], cond: Option[SpqlNode]] = 
  let
    tag      = n.children[0].sval
    hasCond  = n.children[^1].kind in {gkPrefix, gkInfix, gkCall}
    aliasesMaxIndex = 
      if hasCond: n.children.len - 2
      else:       n.children.len - 1
    aliases  = n.children[1..aliasesMaxIndex].mapit it.sval
    cond     = 
      if hasCond: some n.children[^1]
      else:       none SpqlNode

  (tag, aliases, cond)

func sqlCondsOfNode(gn; imap; node: string, varResolver): string {.effectsOf: varResolver.} =
  let inode = imap[node]

  # FIXME find the correspoding node in separate function
  # TODO add support for multiple aliases
  for n in gn.children:
    case n.kind
    of gkDef:
      let di = defInfo n
            
      if node in di.aliases:
        << '('

        if di.tag != ";":
          << fmt"{inode}.{tagCol} == '{di.tag}'"
        
        if di.cond.issome and result.len > 1:
          << " AND " 

        if di.cond.issome:
          << resolveSql(n.children[^1], @[], "normal", inode, varResolver)

        << ')'

        if result.len == 2: # == "()" 
          result = "1"

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
      let di = defInfo n
      
      if edge in di.aliases:
        var acc: seq[string]

        if isrc != ".":
          add acc, fmt"{iedge}.{sourceCol} == {isrc}.{idCol}"

        if itar != ".":
          add acc, fmt"{iedge}.{targetCol} == {itar}.{idCol}"

        case acc.len
        of 0: 
          << '1'
        else:
          << '('
          << acc.join " AND "
          << ')'
        
        return

    else: discard
  raisee fmt"the node '{edge}' not found in query"


func findIdents(gn; result: var seq[string]) =
  case gn.kind
  of gkIdent:
    add result, gn.sval
  
  else:
    for a in gn.children:
      findIdents a, result
  
func selects(gn): seq[string] = 
  findIdents gn, result

func deepIdentReplace(gn; imap) = 
  case gn.kind
  of gkIdent: 
    gn.sval = imap[gn.sval]
  
  of gkWrapper, gkVerb, gkGroupBy, gkHaving, gkOrderBy, gkCase, gkElse, gkWhen, gkInfix, gkPrefix, gkCall:
    for ch in gn.children:
      deepIdentReplace ch, imap

  else:
    discard

func findNode(gn; kind: SpqlKind): Option[SpqlNode] = 
  for ch in gn.children:
    if ch.kind == kind: 
      return some ch

func askedQuery(gn): QueryGraph =
  let n = get gn.findNode gkAsk
  parseQueryGraph n.children.mapIt it.sval

func getVerb*(gn): SpqlNode =
  let m = gn.findNode gkVerb
  if issome m: get m
  else       : raisee "cannot find verb/return"

func getUse(gn): string =
  gn.findNode(gkuse).get.children[0].sval

func getParams(gn): seq[string] =
  gn.findNode(gkParams).get.children ~> it.sval

func getGroup(gn): Option[SpqlNode] = 
  findNode gn, gkGroupBy


func toSqlSelectImpl(gn; relsIdent: seq[string]): string = 
  resolveSql gn, relsIdent, "select", "???", s => "!!!"

func toSqlSelect(verb: SpqlNode, relsIdent: seq[string], imap): string = 
  deepIdentReplace verb, imap
  let mappedRels = relsIdent.map imap

  if verb.visualize:
    let args = verb.children.mapit(
      fmt"""json_array(
        {it.sval}.{idCol}, 
        {it.sval}.{sourceCol}, 
        {it.sval}.{targetCol}
      )"""
    ).join(",")

    fmt"json_array({args})"

  else:
    verb
      .children
      .mapit(toSqlSelectImpl(it, mappedRels))
      .join ", "


# func getRels(gn): seq[string] = 
#   for ch in gn.children:
#     if ch.kind == gkDef:
#       if ch.defkind == defEdge:
#         add result, ch.children[1].sval


func resolve(sqlPat: seq[SqlPatSep], patEdges: seq[string], imap; gn; varResolver): string {.effectsOf: varResolver.} =
  let
    verbs       = gn.getVerb
    revmap      = rev imap

  for i, p in sqlPat:
    result.add:
      case p.kind
      of sqkStr:
        p.content

      of sqkCommand:
        case toUpperAscii p.cmd         
        of "NODE":
          fmt"{nodes} {p.args[0]}"

        of "EDGE":
          fmt"{edges} {p.args[0]}"

        of "CHECK_CONDS":
          sqlCondsOfNode(gn, imap, revmap[p.args[0]], varResolver)

        of "CHECK_RELS":
          sqlCondsOfEdge(gn, imap, revmap[p.args[0]], revmap[p.args[1]], revmap[p.args[2]], varResolver)

        of "EXISTS_EDGE": 
          resolve(
            @[
              SqlPatSep(kind: sqkStr, content: fmt"EXISTS ( SELECT 1 FROM edges {p.args[0]} WHERE "),
              SqlPatSep(kind: sqkCommand, cmd: "CHECK_CONDS", args: @[p.args[0]]),
              SqlPatSep(kind: sqkStr, content: " AND "),
              SqlPatSep(kind: sqkCommand, cmd: "CHECK_RELS", args: p.args),
              SqlPatSep(kind: sqkStr, content: " )")],
            patEdges,
            imap, 
            gn,
            varResolver
          )

        of "GET":
          varResolver p.args[0]


        of "SELECT_FIELDS":
          ## PIN
          toSqlSelect verbs, patEdges, imap

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
                add temp, ' '
                add temp, s.get[i]
              add acc, temp
            
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


func replaceDeepImpl(father: SpqlNode, index: int, gn; lookup: AliasLookup) = 
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


func howToFind(gn): KindOfQuery = 
  var 
    cAsk = 0
    cUse  = 0
  
  for ch in gn.children:
    case ch.kind
    of gkAsk: inc cAsk
    of gkUse: inc cUse
    else:     discard

  let  state = (cAsk, cUse)
  if   state == (1, 0): byPattern
  elif state == (0, 1): byKey
  else: raisee "invalid state: " & $state

func findByPattern(gn; queryStrategies): tuple[qs: QueryStrategy, imap: IdentMap] = 
  for qs in queryStrategies.collection:
    if identMap =? matches(gn.askedQuery, qs.pattern):
      if (gn.getVerb.selects.map identMap) <= qs.selectable:
        return (qs, identMap)

      else:
        discard
        # debugEcho "matched but select items are not matched"

  raisee "no pattern was found"

func toSqlImpl(gn; qs: QueryStrategy, imap; varResolver): SqlQuery {.effectsOf: varResolver.} =
  let edges = qs.edges.map rev imap
  sql resolve(qs.sqlPattern, edges, imap, gn, varResolver)

func toSql*(gn: sink SpqlNode, queryStrategies; varResolver): SqlQuery {.effectsOf: varResolver.} = 
  prepareGQuery gn

  case howToFind gn
  of byPattern:
    let p = findByPattern(gn, queryStrategies)
    return toSqlImpl(gn, p.qs, p.imap, varResolver)
  
  of byKey:
    let 
      u = getUse    gn
      p = getParams gn
      qs   = queryStrategies.table[u]
      imap = makeMap(p, qs.parameters)

    return toSqlImpl(gn, qs, imap, varResolver)


# TODO add guard for insertion
# TODO add insert query, for inserting nodes and edges at once:
when defined insert_query:
  let query = """
    #movie    m
    #person   p1 p2 p3
    #acted_in a

    insert    
      p1>-a->m
      p2>-a->m
  """

  let ctx = %*{
    refs: {
      p1: 12,
      p2: 39,
    },

    docs: {
      p3: {
        name: "Ali Zamani",
      },
      a: nil, # empty doc
      m: {    # doc
        title: "may I pray for you"
      }
    }
  }

  # ids of mentions
  let ans = %*{
    p1: 12,  
    p2: 39,  
    p3: 101,
    a: 247,
    m: 102,
  }

when defined update_ctx:
  let ctx = %*{
    whole: {
      "12": newDoc
    },
    partials: {
      "14": [
        "name.first": "Ali",
        "name.last": "Nejati",
        "age": 17,
      ]
    },
  }