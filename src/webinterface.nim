import std/[json, strformat, with]
import mummy, mummy/routers
import gql


type
  RequestData = object
    query:   string
    context: JsonNode

proc staticFiles(req: Request) =
  discard

proc interactiveApp(req: Request) =
  discard

proc gqlService(req: Request) =
  var headers: HttpHeaders
  headers["Content-Type"] = "text/plain"
  req.respond(200, headers, "Hello, World!")


when isMainModule:
  var router: Router
  # inspired by CouchDB
  with router:
    get  "/",          interactiveApp
    get  "/dist/",     staticFiles

    get  "/api/users/list/",   apiDatabasesOfUser
    get  "/api/users/login/",  apiDatabasesOfUser
    get  "/api/users/signup/", apiDatabasesOfUser
    
    get  "/api/users/<username>/stats/",  apiDatabasesOfUser
    
    get  "/api/users/<username>/databases/all/",        apiDatabasesOfUser
    get  "/api/users/<username>/databases/<db>/stats/",  gqlService
    post "/api/users/<username>/databases/<db>/query/",  gqlService
    
    get  "/api/users/<username>/databases/<db>/index/list/",   gqlService
    post "/api/users/<username>/databases/<db>/index/new/",    gqlService
    post "/api/users/<username>/databases/<db>/index/delete/", gqlService



  let 
    app  = newServer router
    port = 5000 

  echo fmt"Serving on http://localhost:{port}"
  app.serve Port portw