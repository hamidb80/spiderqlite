import std/[json, strformat, with, os, strutils]
import mummy, mummy/routers
import gql



proc staticFiles(req: Request) =
  discard

proc gqlService(req: Request) =
  var headers: HttpHeaders
  headers["Content-Type"] = "text/plain"
  req.respond(200, headers, "Hello, World!")



proc initRouter: Router = 
  with result:
    get    "/",                       interactiveApp
    get    "/static/",                staticFiles

    get    "/api/users/",             apiDatabasesOfUser
    get    "/api/user/",              apiDatabasesOfUser
    get    "/api/login/",             apiDatabasesOfUser
    get    "/api/signup/",            apiDatabasesOfUser
    
    get    "/api/databases/",         apiDatabasesOfUser
    post   "/api/database/",          apiDatabasesOfUser
    get    "/api/database/stats/",    gqlService
    post   "/api/database/query/",    gqlService
    
    post   "/api/database/node/",    gqlService
    post   "/api/database/edge/",    gqlService
    put    "/api/database/nodes/",    gqlService
    put    "/api/database/edges/",    gqlService
    delete "/api/database/nodes/",    gqlService
    delete "/api/database/edges/",    gqlService

    get    "/api/database/indexes/",  gqlService
    post   "/api/database/index/",    gqlService
    delete "/api/database/index/",    gqlService


when isMainModule:
  let 
    server = newServer initRouter()
    host   =           getEnv("host", "localhost")
    port   = parseInt  getEnv("port", "5000")

  echo fmt"Serving on http://{host}:{port}/"
  server.serve Port port
