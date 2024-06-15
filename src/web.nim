import std/[json, strformat, with, os, strutils, sugar, monotimes, times]

import db_connector/db_sqlite
import mummy, mummy/routers

import gql
import ./utils/other


type
  DbEssense = object # TODO put queries in toml file here

func parseTag(s: string): string = 
  s.strip(chars= {'#'})

proc sqlize(s: seq[int]): string = 
  '(' & join(s, ",") & ')'

proc staticFiles(req: Request) =
  discard

proc jsonAffectedRows(n: int, ids: seq[int] = @[]): string = 
  "{\"affected_rows\":" & $n & ", \"ids\": [" & ids.join(",") & "]}"


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





proc getEntity(req: Request, entity, alias, select: string) =
  let
    id     = req.queryParams["id"]
    db     = openSqliteDB    "./temp/graph.db"
    row = db.getRow(sql fmt"""
      SELECT {select}
      FROM   {entity} {alias}
      WHERE  id = ?
    """, id)

  close db
  req.respond(200, emptyHttpHeaders(), row[0])

proc getNode(req: Request) =
  getEntity req, "nodes", "n", sqlJsonNodeExpr "n"
  
proc getEdge(req: Request) =
  getEntity req, "edges", "e", sqlJsonEdgeExpr "e"


# TODO add minimal option if enables only returns "_id"
proc createNode(req: Request) =
  let
    j      = parseJson req.body
    tag    = parseTag getstr j["tag"]
    doc    =                $j["doc"]
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
    tag    = parseTag getstr j["tag"]
    source =          getInt j["source"]
    target =          getInt j["target"]
    doc    =                $j["doc"]
    db     = openSqliteDB    "./temp/graph.db"

  let id = db.insertID(sql """
    INSERT INTO
    edges  (tag, source, target, doc) 
    VALUES (?,   ?,      ?,      ?)
  """, tag, source, target, doc)

  close db
  req.respond(200, emptyHttpHeaders(), "{\"_id\":" & $id & "}")


proc updateEntity(req: Request, entity: string) =
  let
    j   = parseJson req.body
    db  = openSqliteDB    "./temp/graph.db"

  assert j.kind == JObject
  var acc: seq[int]
  for k, v in j:
    let 
      id       = parseint k
      doc      = $v
      affected = db.execAffectedRows(sql fmt"""
        UPDATE {entity}
        SET    doc = ?
        WHERE  id  = ?
      """, doc, id)

    if affected == 1:
      acc.add affected

  close db
  req.respond(200, emptyHttpHeaders(), jsonAffectedRows(acc.len, acc))

proc updateNodes(req: Request) =
  updateEntity req, "nodes"

proc updateEdges(req: Request) =
  updateEntity req, "edges"


proc deleteEntity(req: Request, entity: string) =
  let
    j        = parseJson req.body
    ids      = j["ids"].to seq[int]
    db       = openSqliteDB    "./temp/graph.db"
    affected = db.execAffectedRows(sql fmt"""
      DELETE FROM  {entity}
      WHERE  id IN {sqlize ids} 
    """)

  close db
  req.respond(200, emptyHttpHeaders(), jsonAffectedRows affected)

proc deleteNodes(req: Request) =
  deleteEntity req, "nodes"

proc deleteEdges(req: Request) =
  deleteEntity req, "edges"



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
