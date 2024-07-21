import std/[strformat, strutils]

import db_connector/db_sqlite

import core
import ../utils/other

# --------- utils ------------------------------------

func parseTag*(s: string): string = 
  if s.isEmptyOrWhitespace: raisee "empty tag"
  elif s[0] in {'#', '@'}:  s.substr 1
  else:                     s

func sqlize(s: seq[int]): string = 
  '(' & s.joinComma & ')'

# --------- query gen --------------------------------

func prepareSchemaInitQuery*: SqlQuery = 
  sql"""
    PRAGMA encoding="UTF-8";

    -- tables

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

    -- indexes

    CREATE INDEX IF NOT EXISTS node_index         ON nodes(id);
    CREATE INDEX IF NOT EXISTS node_tag_index     ON nodes(tag);

    CREATE INDEX IF NOT EXISTS edges_index        ON edges(id);
    CREATE INDEX IF NOT EXISTS edges_source_index ON edges(source);
    CREATE INDEX IF NOT EXISTS edges_target_index ON edges(target);
  """


func prepareGetQuery*(entity: Entity): SqlQuery = 
  let select = case entity
  of nodes: sqlJsonNodeExpr "" 
  of edges: sqlJsonEdgeExpr ""

  sql fmt"""
    SELECT {select}
    FROM   {entity}
    WHERE  id = ?
  """

func prepareUpdateQuery*(entity: Entity): SqlQuery = 
  sql fmt"""
    UPDATE {entity}
    SET    doc = ?
    WHERE  id  = ?
  """


func prepareNodeInsertQuery*: SqlQuery = 
  sql """
    INSERT INTO
    nodes  (tag, doc) 
    VALUES (?,   ?)
  """

func prepareEdgeInsertQuery*: SqlQuery = 
  sql """
    INSERT INTO
    edges  (tag, source, target, doc) 
    VALUES (?,   ?,      ?,      ?)
  """


func prepareDeleteQuery*(entity: Entity, ids: seq[int]): SqlQuery = 
  sql fmt"""
    DELETE FROM  {entity}
    WHERE  id in {sqlize ids}
  """

# ----------------------------------------------------