import std/[strformat, strutils, json, sugar]

import db_connector/db_sqlite

import ./query_language/[core, parser, queries]
import ./utils/other

# --------- utils ------------------------------------

type
  Tag* = distinct string
  Id* = int


func parseTag*(s: string): Tag =
  if s.isEmptyOrWhitespace: raisee "empty tag"
  elif s[0] in {'#', '@'}: Tag s[1..^1]
  else: Tag s

# ----------------------------------------------------

using
  db:   DbConn
  q :   SqlQuery
  spql: SpqlNode
  
  tag: Tag
  ent: Entity
  doc: JsonNode
  ctx: (s: string) -> string
  
  id:      Id
  ids: seq[Id]

  src, tar: Id

  queryStrateies: QueryStrategies



proc initDbSchema*(db) =
  for q in schemaInitQueries:
    exec db, q


proc getEntitiesDbRaw*(db, ids, ent): string =
  let query = getEntitiesQuery(ids, ent)
  getRow(db, query)[0]

proc getNodesDB*(db, ids): JsonNode =
  parseJson getEntitiesDbRaw(db, ids, nodes)

proc getEdgesDB*(db, ids): JsonNode =
  parseJson getEntitiesDbRaw(db, ids, edges)


proc getEntityDbRaw*(db, id, ent): string =
  let
    query = getEntityQuery ent
    row = getRow(db, query, id)
  row[0] # first g

proc getNodeDB*(db, id): JsonNode =
  parseJson getEntityDbRaw(db, id, nodes)

proc getEdgeDB*(db, id): JsonNode =
  parseJson getEntityDbRaw(db, id, edges)




proc insertNodeDB*(db, tag, doc): Id =
  insertID db, nodeInsertQuery, string tag, $doc

proc insertEdgeDB*(db, tag, doc, src, tar): Id =
  insertID db, edgeInsertQuery, string tag, $doc, src, tar


proc deleteEntitiesDB*(db, ent, ids): Natural =
  execAffectedRows db, deleteEntitiesQuery(ent, ids)

proc deleteNodesDB*(db, ids): Natural =
  deleteEntitiesDB db, nodes, ids

proc deleteEdgesDB*(db, ids): Natural =
  deleteEntitiesDB db, edges, ids

proc deleteNodeDB*(db, id): Natural =
  deleteEntitiesDB db, nodes, @[id]

proc deleteEdgeDB*(db, id): Natural =
  deleteEntitiesDB db, edges, @[id]


proc updateNodeDocDB*(db, id, doc): bool =
  1 == execAffectedRows(db, nodeUpdateDocQuery, $doc, id)

proc updateEdgeDocDB*(db, id, doc): bool =
  1 == execAffectedRows(db, edgeUpdateDocQuery, $doc, id)

proc updateEntityDocDB*(db, ent, id, doc): bool =
  case ent
  of nodes: updateNodeDocDB db, id, doc 
  of edges: updateEdgeDocDB db, id, doc

proc askQueryDbRaw*(db, ctx, spql, queryStrateies): string = 
  let sql = toSql(spql, queryStrateies, ctx)

  result = newStringOfCap 1024 * 20 # KB
  << "{\"result\":["

  var rows = 0
  for row in db.fastRows sql:
    inc rows
    let r   = row[0]
    if r[0] in {'[', '{'} or (r.len < 20 and isNumber r): << r
    else:                                                 << escapeJson r
    << ','

  if result[^1] == ',': # check for 0 results
    result.less

  << "],\"length\":"
  << $rows

  # << ','
  # << "\"performance\":{"
  # << "\"unit\": \"us\""
  # << ','
  # << "\"total\":"
  # << $inMicroseconds(tcollect - thead)
  # << ','
  # << "\"parse body\":"
  # << $inMicroseconds(tparsejson - thead)
  # << ','
  # << "\"parse query\":"
  # << $inMicroseconds(tparseq - tparsejson)
  # << ','
  # << "\"query matching & conversion\":"
  # << $inMicroseconds(tquery - tparseq)
  # << ','
  # << "\"exec & collect\":"
  # << $inMicroseconds(tcollect - tquery)
  << '}'

proc askQueryDB*(db, ctx, spql, queryStrateies): JsonNode = 
  parseJson askQueryDbRaw(db, ctx, spql, queryStrateies)


proc countEntitiesDB*(db, ent): seq[tuple[tag: string, count: int, doc: JsonNode]] =
  for row in db.rows countEntitiesQuery ent:
    add result, (row[0], parseInt row[1], parseJson row[3])
