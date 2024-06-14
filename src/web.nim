import std/[json, strformat, with, os, strutils, sugar]

import db_connector/db_sqlite
import mummy, mummy/routers

import gql
import ./utils/other



proc staticFiles(req: Request) =
  discard

proc askQuery(req: Request) {.gcsafe.} =
  let 
    queryStrategies = parseQueryStrategies parseToml readfile "./examples/qs.toml"
    j               = req.body.parseJson
    gql             = parseGql getstr  j["query"]
    ctx             =                  j["context"]
    singleColumn    =          getBool j["singleColumn"]
    db              = openSqliteDB    "./temp/graph.db"
  
    sql = toSql(
      gql, 
      queryStrategies, 
      s => $ctx[s])

  # echo sql

  var resj = newJArray()
  for row in db.getAllRows sql:
    if singleColumn:
      resj.add parseJson row[0]
    else:
      var rowj = newJArray()
      for cell in row:
        rowj.add parseJson cell
      resj.add rowj
  req.respond 200, emptyHttpHeaders(), $resj

proc gqlService(req: Request) =
  var headers: HttpHeaders
  headers["Content-Type"] = "text/plain"
  req.respond(200, headers, "Hello, World!")


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
    
    post   "/api/database/node/",    gqlService
    post   "/api/database/edge/",    gqlService
    put    "/api/database/nodes/",    gqlService
    put    "/api/database/edges/",    gqlService
    delete "/api/database/nodes/",    gqlService
    delete "/api/database/edges/",    gqlService

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
