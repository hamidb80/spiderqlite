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
    get    "/",                                interactiveApp
    get    "/dist/",                           staticFiles

    get    "/api/list_of_users/",                  apiDatabasesOfUser
    get    "/api/login/",                 apiDatabasesOfUser
    get    "/api/signup/",                apiDatabasesOfUser
    
    post   "/api/new_database/",                  apiDatabasesOfUser
    get    "/api/all_databasese/",                  apiDatabasesOfUser
    get    "/api/database_statistics/",  gqlService
    post   "/api/query_database/",  gqlService
    
    post   "/api/new_node/",          gqlService
    post   "/api/new_edge/",          gqlService
    put    "/api/update_edges/",  gqlService
    put    "/api/update_nodes/",  gqlService
    delete "/api/delete_edges/",  gqlService
    delete "/api/delete_nodes/",  gqlService

    get    "/api/list_of_indexes/",  gqlService
    post   "/api/new_index/",        gqlService
    delete "/api/delete_index/"   ,  gqlService


when isMainModule:
  let 
    server = newServer initRouter()
    host   =           getEnv("host", "localhost")
    port   = parseInt  getEnv("port", "5000")

  echo fmt"Serving on http://{host}:{port}/"
  server.serve Port port
