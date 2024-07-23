import std/[strutils, strformat]

import db_connector/db_sqlite

import ./core
import ../utils/[other]


# --------- query gen --------------------------------

func splitSqlQueries(stmts: string): seq[SqlQuery] =
  for s in stmts.split ';':
    if not isEmptyOrWhitespace s:
      add result, sql s

func sqlize(s: seq[int]): string =
  '(' & s.joinComma & ')'


const schemaInitQueries* = splitSqlQueries fmt"""
  PRAGMA encoding="UTF-8";

  CREATE TABLE IF NOT EXISTS nodes (
      {idCol}          INTEGER PRIMARY KEY,
      {tagCol}         TEXT,
      {docCol}         JSON NOT NULL
  );

  CREATE TABLE IF NOT EXISTS edges (
      {idCol}       INTEGER PRIMARY KEY,
      {tagCol}      TEXT,
      {docCol}      JSON,
      {sourceCol}   INTEGER,
      {targetCol}   INTEGER,

      FOREIGN KEY ({sourceCol}) REFERENCES nodes({idCol}),
      FOREIGN KEY ({targetCol}) REFERENCES nodes({idCol})
  );


  CREATE INDEX IF NOT EXISTS node_index         ON nodes({idCol});
  CREATE INDEX IF NOT EXISTS node_tag_index     ON nodes({tagCol});

  CREATE INDEX IF NOT EXISTS edges_index        ON edges({idCol});
  CREATE INDEX IF NOT EXISTS edges_source_index ON edges({sourceCol});
  CREATE INDEX IF NOT EXISTS edges_target_index ON edges({targetCol});
"""

const nodeInsertQuery* = sql fmt"""
  INSERT INTO
  nodes  ({tagCol}, {docCol}) 
  VALUES (?       , ?)
"""

const edgeInsertQuery* = sql fmt"""
  INSERT INTO
  edges  ({tagCol}, {docCol}, {sourceCol}, {targetCol})
  VALUES (?       , ?       , ?          , ?)
"""

const nodeUpdateDocQuery* = sql fmt"""
  UPDATE nodes
  SET    {docCol} = ?
  WHERE  {idCol}  = ?
"""

const edgeUpdateDocQuery* = sql fmt"""
  UPDATE edges
  SET    {docCol} = ?
  WHERE  {idCol}  = ?
"""


func getEntityQuery*(entity: Entity): SqlQuery =
  let select = case entity
  of nodes: sqlJsonNodeExpr ""
  of edges: sqlJsonEdgeExpr ""

  sql fmt"""
    SELECT {select}
    FROM   {entity}
    WHERE  {idCol} = ?
  """

func deleteEntitiesQuery*(entity: Entity, ids: seq[int]): SqlQuery =
  sql fmt"""
    DELETE 
    FROM   {entity}
    WHERE  {idCol} in {sqlize ids}
  """
