import std/[strutils, json, nre]
import db_connector/db_sqlite
import ./utils
import pretty # debug print

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

    gkTake # select take

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
    
    gkWrapper

  GqlNode = ref object
    kind: GqlKind
    children: seq[GqlNode]

  AskPatKind = enum
    apkNode
    apkArrow

  ArrowDir = enum
    headL2R # >-
    tailL2R # ->
    headR2L # -<
    tailR2L # <-

  AskPatNode = object
    case kind: AskPatKind
    
    of apkNode:
      ident: string
      starred: bool
    
    of apkArrow:
      dir: ArrowDir

  PatObj = object
    ask: seq[AskPatNode]
    selectable: seq[string]


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

proc parseGql(content: string): GqlNode = 
  result = GqlNode(kind: gkWrapper)

  type
    Temp = tuple
      node: GqlNode
      indentLevel: int

  var 
    nested: seq[Temp]= @[(result, -1)]

  proc getParent(indent: Natural): GqlNode = 
    while not empty nested:
      let p = nested.last
      if  p.indentLevel >= indent:
        prune nested
      else:
        return p.node

  for line in splitLines content:
    if not isEmptyOrWhitespace line:
      let 
        ind     = indentation line
        key     = cmd(ind, line)
        parent  = getParent ind
        # tokens = 
        n = 
          case key
          of "--":             parseComment
          of "\"":             parseString
          of "0", "1", "2", 
             "3", "4", "5", 
             "6", "7", "8", 
             "9"             : parseNumber
          of "#":              parseDefHeader
          of "<", "<=", "==", 
              "!=", ">=", ">",
              "AND", "OR"    : parseInfix
          of "ASK", "FROM":    parseAsk
          of "TAKE", "SELECT": parseSelect
          else: raise newException(ValueError, key)

      parent.children.add n
      nested         .add (n, ind)

func q(askedPattern, selectables: string): PatObj  = 
  result.selectable = split selectables
  for kw in askedPattern.findAll re"\*?\w+|[-<>]{2}":
    result.ask.add:
      case kw
      of ">-": AskPatNode(kind: apkArrow, dir: headL2R)
      of "->": AskPatNode(kind: apkArrow, dir: tailL2R)
      of "-<": AskPatNode(kind: apkArrow, dir: headR2L)
      of "<-": AskPatNode(kind: apkArrow, dir: tailR2L)
      else:
        let (starred, id) = 
          if kw[0] == '*': (true,  kw.substr 1)
          else:            (false, kw)

        AskPatNode(
          kind: apkNode, 
          ident: id, 
          starred: starred)

# pattern : what can be taken as result 
# * means primary i.e. where query starts
let queryStrategies = {

    q("*a>-c->b", "a b c"): dedent """
      SELECT 
        |select_fields|
      FROM
        nodes a,
      JOIN 
        edges c
        nodes b
      ON
        |check_edge c a b|
        |check_node b|
      WHERE 
        |check_node a|
      |sort_clause|
      |offset_clause|
      |limit_clause|
    """,

  q("a>-*c->b",          "a b c"): dedent """
      SELECT 
        |select_fields|
      FROM
        edges c
      JOIN 
        nodes a,
        nodes b
      ON
        |check_node a|
        |check_node b|
      WHERE 
        |check_edge c a b|
      |sort_clause|
      |offset_clause|
      |limit_clause|
    """,
  
  q("a>-c->*b", "a b c"): dedent """
      SELECT 
        |select_fields|
      FROM
        nodes b,
      JOIN 
        edges c
        nodes a
      ON
        |check_edge c a b|
        |check_node a|
      WHERE 
        |check_node b|
      |sort_clause|
      |offset_clause|
      |limit_clause|
    """,

  q("*a>-c1->b>-!c2->a", "a b c1"): """
      SELECT 
        |select_fields|
      FROM
        nodes a
      JOIN 
        edges c1,
        nodes b
      ON
        |check_edge c1 a b|
        AND
        NOT EXISTS |exists_edge c2 a b|
      WHERE 
        |a.conds|
      |sort_clause|
      |offset_clause|
      |limit_clause|
""",
}

func matches(pattern, query: string): bool = 
  false

func resolve(q: GqlNode, ctx: JsonNode): GqlNode= 
  discard

proc toSql(q: GqlNode): SqlQuery = 
  for (p, a) in queryStrategies:
    discard
    # if matches(p, q):
      # return p.resolve q

  raise newException(ValueError, "such pattern is not defined")


when isMainModule:
  let
    parsedQl = parseGql readFile "./test/sakila/get.gql"
    # mname = "ACADEMY DINOSAUR"
    # ctx   = %*{"movie": {"title": mname}} 
    # nq    = parsedQl.resolve ctx
  
  # echo tosql parseGql
  print parsedQl
