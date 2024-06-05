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
    post "/api/gql/",  gqlService
    post "/api/data/",  gqlService

  let 
    app  = newServer router
    port = 5000 

  echo fmt"Serving on http://localhost:{port}"
  app.serve Port port