import std/[json, strformat, with, os, strutils, sugar, monotimes, times]

import db_connector/db_sqlite
import mummy, mummy/routers

import gql
import ./utils/other



proc staticFiles(req: Request) =
  discard


let queryStrategies {.global.} = parseQueryStrategies parseToml readfile "./examples/qs.toml"

proc defaultQueryStrategies: seq[QueryStrategy] =
  ignore:
    return queryStrategies

proc askQuery(req: Request) {.gcsafe.} =
  let 
    thead = getMonoTime()
    j               = parseJson req.body
    gql             = parseGql  getstr  j["query"]
    ctx             =                   j["context"]
    tprepare        = getMonoTime()
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
    add "\"prepare\":"
    add $inMicroseconds(tprepare - thead)
    add ','
    add "\"openning db\":"
    add $inMicroseconds(topenDb - tprepare)
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
