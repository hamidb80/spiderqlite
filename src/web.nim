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
    get    "/",                                     interactiveApp
    get    "/dist/",                                staticFiles

    get    "/api/user/list/",                       apiDatabasesOfUser
    get    "/api/user/login/",                      apiDatabasesOfUser
    get    "/api/user/signup/",                     apiDatabasesOfUser
    
    post   "/api/database/new/",                    apiDatabasesOfUser
    get    "/api/database/all/",                    apiDatabasesOfUser
    get    "/api/database/<db>/stats/",             gqlService
    post   "/api/database/<db>/query/",             gqlService
    
    post   "/api/database/<db>/new/node/",          gqlService
    post   "/api/database/<db>/new/edge/",          gqlService
    put    "/api/database/<db>/edges/",             gqlService
    put    "/api/database/<db>/nodes/",             gqlService
    delete "/api/database/<db>/edges/",             gqlService
    delete "/api/database/<db>/nodes/",             gqlService

    get    "/api/database/<db>/index/list/",        gqlService
    post   "/api/database/<db>/index/new/",         gqlService
    delete "/api/database/<db>/index/<indexname>/", gqlService


when isMainModule:
  let 
    server = newServer initRouter()
    host   =           getEnv("host", "localhost")
    port   = parseInt  getEnv("port", "5000")

  echo fmt"Serving on http://{host}:{port}/"
  server.serve Port port
