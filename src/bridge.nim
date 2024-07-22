import std/[strformat, strutils, json, sugar]

import db_connector/db_sqlite

import ./query_language/[core, parser]
import ./utils/other

# --------- utils ------------------------------------

type
  Tag* = distinct string
  Id* = int


func parseTag*(s: string): Tag =
  if s.isEmptyOrWhitespace: raisee "empty tag"
  elif s[0] in {'#', '@'}: Tag s[1..^1]
  else: Tag s

func sqlize(s: seq[int]): string =
  '(' & s.joinComma & ')'

func splitSqlQueries(stmts: string): seq[SqlQuery] =
  for s in stmts.split ';':
    if not isEmptyOrWhitespace s:
      add result, sql s

# --------- query gen --------------------------------

const schemaInitQueries* = splitSqlQueries """
  PRAGMA encoding="UTF-8";


  CREATE TABLE IF NOT EXISTS nodes (
      id          INTEGER PRIMARY KEY,
      tag         TEXT,
      doc         JSON NOT NULL
  );

  CREATE TABLE IF NOT EXISTS edges (
      id          INTEGER PRIMARY KEY,
      tag         TEXT,
      doc         JSON    DEFAULT '{}',
      source      INTEGER,
      target      INTEGER,

      FOREIGN KEY (source) REFERENCES nodes(id),
      FOREIGN KEY (target) REFERENCES nodes(id)
  );


  CREATE INDEX IF NOT EXISTS node_index         ON nodes(id);
  CREATE INDEX IF NOT EXISTS node_tag_index     ON nodes(tag);

  CREATE INDEX IF NOT EXISTS edges_index        ON edges(id);
  CREATE INDEX IF NOT EXISTS edges_source_index ON edges(source);
  CREATE INDEX IF NOT EXISTS edges_target_index ON edges(target);
"""

const nodeInsertQuery* = sql """
  INSERT INTO
  nodes  (tag, doc) 
  VALUES (?,   ?)
"""

const edgeInsertQuery* = sql """
  INSERT INTO
  edges  (tag, source, target, doc) 
  VALUES (?,   ?,      ?,      ?)
"""

const nodeUpdateDocQuery* = sql"""
  UPDATE nodes
  SET    doc = ?
  WHERE  id  = ?
"""

const edgeUpdateDocQuery* = sql"""
  UPDATE edges
  SET    doc = ?
  WHERE  id  = ?
"""


func getEntityQuery*(entity: Entity): SqlQuery =
  let select = case entity
  of nodes: sqlJsonNodeExpr ""
  of edges: sqlJsonEdgeExpr ""

  sql fmt"""
    SELECT {select}
    FROM   {entity}
    WHERE  id = ?
  """

func deleteEntitiesQuery*(entity: Entity, ids: seq[int]): SqlQuery =
  sql fmt"""
    DELETE FROM  {entity}
    WHERE  id in {sqlize ids}
  """

# ----------------------------------------------------

using
  db:   DbConn
  q :   SqlQuery
  spql: SpqlNode
  
  tag: Tag
  ent: Entity
  doc: JsonNode
  ctx: JsonNode
  
  id:      Id
  ids: seq[Id]



proc initDbSchema*(db) =
  for q in schemaInitQueries:
    exec db, q


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

proc insertEdgeDB*(db, tag, doc): Id =
  insertID db, edgeInsertQuery, string tag, $doc


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


proc askQueryDbRaw*(db, ctx, spql; queryStrateies: QueryStrategies): string = 
  let
    ctxGetter = (s: string) => $ctx[s]
    sql       = toSql(spql, queryStrateies, ctxGetter)

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
  << '}'

  # TODO add/fill perf
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
  # << '}'

proc askQueryDB*(db, ctx, spql; queryStrateies: QueryStrategies): JsonNode = 
  parseJson askQueryDbRaw(db, ctx, spql, queryStrateies)
