import std/[json, strformat, with, os, strutils, sugar, monotimes, times]

import db_connector/db_sqlite
import mummy, mummy/routers

import gql
import ./utils/other


type
  DbEssense = object # TODO put queries in toml file here


proc sqlize(s: seq[int]): string = 
  '(' & join(s, ",") & ')'

proc staticFiles(req: Request) =
  discard


let queryStrategies {.global.} = parseQueryStrategies parseToml readfile "./examples/qs.toml"

proc defaultQueryStrategies: QueryStrategies =
  ignore:
    return queryStrategies

proc askQuery(req: Request) {.gcsafe.} =
  let 
    thead           = getMonoTime()
    j               = parseJson req.body
    ctx             = j["context"]
    tparsejson      = getMonoTime()
    gql             = parseGql  getstr  j["query"]
    tparseq         = getMonoTime()
    db              = openSqliteDB    "./temp/graph.db"
    topenDb         = getMonoTime()
    sql             = toSql(
      gql, 
      defaultQueryStrategies(), 
      s => $ctx[s])
    tquery          = getMonoTime()

  # echo sql

  var acc = "{\"result\": ["
  
  for row in db.fastRows sql:
    acc.add row[0]
    acc.add ','

  if acc[^1] == ',': # check for 0 results
    acc.less
    
  acc.add ']'

  let tcollect = getMonoTime()

  with acc:
    add ','
    add "\"performance\":{"
    add "\"unit\": \"us\""
    add ','
    add "\"total\":"
    add $inMicroseconds(tcollect - thead)
    add ','
    add "\"parse body\":"
    add $inMicroseconds(tparsejson - thead)
    add ','
    add "\"parse query\":"
    add $inMicroseconds(tparseq - tparsejson)
    add ','
    add "\"openning db\":"
    add $inMicroseconds(topenDb - tparseq)
    add ','
    add "\"query matching & conversion\":"
    add $inMicroseconds(tquery - topenDb)
    add ','
    add "\"exec & collect\":"
    add $inMicroseconds(tcollect - tquery)
    add '}'
    add '}'

  close db
  req.respond 200, emptyHttpHeaders(), acc



proc getNode(req: Request) =
  let
    id     = req.queryParams["id"]
    db     = openSqliteDB    "./temp/graph.db"
    row = db.getRow(sql fmt"""
      SELECT {sqlJsonNodeExpr "n"}
      FROM nodes n
      WHERE id = ?
    """, id)

  close db
  req.respond(200, emptyHttpHeaders(), row[0])

proc getEdge(req: Request) =
  let
    id     = req.queryParams["id"]
    db     = openSqliteDB    "./temp/graph.db"
    row = db.getRow(sql fmt"""
      SELECT {sqlJsonEdgeExpr "e"}
      FROM edges e
      WHERE id = ?
    """, id)

  close db
  req.respond(200, emptyHttpHeaders(), row[0])

# TODO add minimal option if enables only returns "_id"
proc createNode(req: Request) =
  let
    j      = parseJson req.body
    tag    = getstr j["tag"]
    doc    =       $j["doc"]
    db     = openSqliteDB    "./temp/graph.db"

  let id = db.insertID(sql """
    INSERT INTO
    nodes  (tag, doc) 
    VALUES (?,   ?)
  """, tag, doc)

  close db
  req.respond(200, emptyHttpHeaders(), "{\"_id\":" & $id & "}")

proc createEdge(req: Request) =
  let
    j      = parseJson req.body
    tag    = getstr j["tag"]
    source = getInt j["source"]
    target = getInt j["target"]
    doc    =       $j["doc"]
    db     = openSqliteDB    "./temp/graph.db"

  let id = db.insertID(sql """
    INSERT INTO
    edges  (tag, source, target, doc) 
    VALUES (?,   ?,      ?,      doc)
  """, tag, source, target, doc)

  close db
  req.respond(200, emptyHttpHeaders(), "{\"_id\":" & $id & "}")


proc updateNodes(req: Request) =
  let
    j   = parseJson req.body
    db  = openSqliteDB    "./temp/graph.db"

  assert j.kind == JObject
  var acc = 0
  for k, v in j:
    let 
      id       = parseint k
      doc      = $v
      affected = db.execAffectedRows(sql """
        UPDATE nodes
        SET    doc = ?
        WHERE  id  = ?
      """, doc, id)

    acc.inc affected

  close db
  req.respond(200, emptyHttpHeaders(), "{\"affected_rows\":" & $acc & "}")

proc updateEdges(req: Request) =
  let
    j   = parseJson req.body
    db  = openSqliteDB    "./temp/graph.db"

  assert j.kind == JObject
  var acc = 0
  for k, v in j:
    let 
      id       = parseint k
      doc      = $v
      affected = db.execAffectedRows(sql """
        UPDATE edges
        SET    doc = ?
        WHERE  id  = ?
      """, doc, id)

    acc.inc affected

  close db
  req.respond(200, emptyHttpHeaders(), "{\"affected_rows\":" & $acc & "}")

proc deleteNodes(req: Request) =
  let
    j        = parseJson req.body
    ids      = j["ids"].to seq[int]
    db       = openSqliteDB    "./temp/graph.db"
    affected = db.execAffectedRows(sql fmt"""
      DELETE FROM nodes
      WHERE  id IN {sqlize ids} 
    """)

  close db
  req.respond(200, emptyHttpHeaders(), "{\"affected_rows\":" & $affected & "}")

proc deleteEdges(req: Request) =
  let
    j        = parseJson req.body
    ids      = j["ids"].to seq[int]
    db       = openSqliteDB    "./temp/graph.db"
    affected = db.execAffectedRows(sql fmt"""
      DELETE FROM edges
      WHERE  id IN {sqlize ids} 
    """)

  close db
  req.respond(200, emptyHttpHeaders(), "{\"affected_rows\":" & $affected & "}")



proc initRouter: Router = 
  with result:
    # get    "/",                       interactiveApp
    get    "/static/",                staticFiles

    # get    "/api/users/",             apiDatabasesOfUser
    # get    "/api/user/",              apiDatabasesOfUser
    # get    "/api/login/",             apiDatabasesOfUser
    # get    "/api/signup/",            apiDatabasesOfUser
    
    # get    "/api/databases/",         apiDatabasesOfUser
    # post   "/api/database/",          apiDatabasesOfUser
    # get    "/api/database/stats/",    gqlService
    post   "/api/database/query/",    askQuery


    get    "/api/database/node/",     getNode
    get    "/api/database/edge/",     getEdge
    
    post   "/api/database/node/",     createNode
    post   "/api/database/node/",     createEdge
    
    put    "/api/database/nodes/",    updateNodes
    put    "/api/database/nodes/",    updateEdges

    delete "/api/database/nodes/",    deleteNodes
    delete "/api/database/edges/",    deleteEdges
    
    # get    "/api/database/indexes/",  gqlService
    # post   "/api/database/index/",    gqlService
    # delete "/api/database/index/",    gqlService


when isMainModule:
  let 
    server = newServer initRouter()
    host   =           getEnv("host", "localhost")
    port   = parseInt  getEnv("port", "6001")

  echo fmt"Serving on http://{host}:{port}/"
  serve server, Port port, host
