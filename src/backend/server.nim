import std/[strutils, strformat, tables, json, monotimes, os, times, with, sugar, uri, mimetypes]

import db_connector/db_sqlite
import mummy, mummy/routers
import webby
import parsetoml
import cookiejar
# TODO use waterpark

import ../query_language/[parser, core]
import ../utils/other
import ../bridge

import ./view
import ./config


type
  App* = object
    server*: Server
    config*: AppConfig
    defaultQueryStrategies*: QueryStrategies

using 
  req: Request


proc getMimetype(ext: string): string = 
  # XXX move out for performance
  var m = newMimetypes()
  m.getMimetype ext


func jsonHeader: HttpHeaders = 
  toWebby @{"Content-Type": "application/json"}


func jsonAffectedRows(n: int, ids: seq[int] = @[]): string = 
  "{" & 
  "\"affected_rows\":" & $n & ", " & 
  "\"ids\": [" & ids.joinComma & "] " & 
  "}"

func jsonError(msg, stackTrace: string): string = 
  "{" & 
  "\"error\": {\"message\": " & msg.escapeJson & "}, " & 
  "\"stack-trace\": " &         stackTrace             & 
  "}"

func decodedQuery(body: string): Table[string, string] = 
  for (key, val) in decodeQuery body:
    result[key] = val


func isPost(req): bool = 
  req.httpmethod == "POST"

# func jsonToSql(j: JsonNode): string = 
#   case j.kind
#   of JInt:    $j.getInt
#   of JFloat:  $j.getFloat
#   of JNull:   "NULL"
#   of JString: dbQuote getStr j
#   of JBool:   $j.getBool
#   else: 
#     raisee "invalid json kind: " & $j.kind


func extractStrategies(tv: TomlValueRef): seq[TomlValueRef] = 
  getElems tv["strategies"]

proc initApp(config: AppConfig): App = 
  var app = App(config: config)

  template logBody: untyped =
    if app.config.logs.reqbody:
      echo req.body

  template logSql(q): untyped =
    if app.config.logs.sql:
      echo q

  proc getDB: DbConn = 
    openSqliteDB app.config.storage.appDbFile

  template withDb(body): untyped =
    # TODO error handling
    let db {.inject.} = getDB()
    body
    close db
    
  template logPerf(body): untyped =
    let thead = getMonoTime()
    body
    let ttail = getMonoTime()
    if app.config.logs.performance:
      let tdelta = ttail - thead
      echo inMicroseconds tdelta, "us"
    

  unwrap controllers:
    # XXX add logPerf and logBody in middleware
    # XXX insert logSql somehow
    
    proc askQueryApi(req) =
      try:
        let j = parseJson req.body
        withdb:
          req.respond 200, jsonHeader(), askQueryDbRaw(db, 
            j["context"], 
            parseSpql getstr j["query"], 
            app.defaultQueryStrategies)

      except:
        let 
          e  = getCurrentException()
          me = getCurrentExceptionMsg()
          je = jsonError(me, e.getStackTrace())
        req.respond 400, jsonHeader(), je
        echo "did error ", je


    proc getEntity(req; ent: Entity) =
      let id    = parseInt   req.queryParams["id"]
      withDB:
        let val   = getEntityDB(db, id, ent)
    
      # XXX logSql
      req.respond 200, jsonHeader(), val

    proc getNodeApi(req) = getEntity req, nodes
    proc getEdgeApi(req) = getEntity req, edges


    proc insertEntities(req; inserter: proc(db: DbConn, t: Tag, doc: JsonNode): Id) {.effectsOf: inserter.} =
      let j = parseJson req.body
      withDB:
        let ids = collect:
          for n in j:
            inserter db, parseTag getstr n["tag"], n["doc"]

      req.respond 200, jsonHeader(), jsonAffectedRows(len ids, ids)

    proc insertNodesApi(req) = insertEntities req, insertNodeDB
    proc insertEdgesApi(req) = insertEntities req, insertEdgeDB


    proc updateEntity(req; ent: Entity) =
      let j = parseJson req.body
      # logSql q

      case j.kind
      of JObject:
        withDB:
          var acc: seq[int]
          for key, doc in j:
            let id = parseInt key
            if updateEntityDocDB(db, ent, id, doc):
              add acc, id

        req.respond 200, jsonHeader(), jsonAffectedRows(len acc, acc)
      
      else:
        raisee "invalid json object for update. it should be object of {id => new_doc}"

    proc updateNodesApi(req) = updateEntity req, nodes
    proc updateEdgesApi(req) = updateEntity req, edges


    proc deleteEntity(req; ent: Entity) =
      let
        j        = parseJson req.body
        ids      = j["ids"].to seq[int]
      withDB:
        let affected = deleteEntitiesDB(db, ent, ids)
      req.respond 200, jsonHeader(), jsonAffectedRows affected

    proc deleteNodesApi(req) = deleteEntity req, nodes
    proc deleteEdgesApi(req) = deleteEntity req, edges

    # ------------------------

    proc staticFilesServ(req) =
      let
        fname   = "./assets/" & req.uri.splitPath.tail
        ext     = fname.splitFile.ext.strip(chars= {'.'}, trailing = false)
        content = readfile fname

      req.respond 200, toWebby @{"Content-Type": getMimetype ext} , content

    proc indexPage(req) =
      req.respond 200, emptyHttpHeaders(), landingPageHtml()

    proc signupPage(req) =
      req.respond 200, emptyHttpHeaders(), signinPageHtml()


    const authKey = "auth"

    proc signOutCookieSet: webby.HttpHeaders =
      result["Set-Cookie"] = $initCookie(authKey, "", path = "/")

    proc signoutPage(req) =
      req.respond 200, signOutCookieSet(), "redirecting to ... XXX"

    # proc signin


    proc signinPage(req) =
      if isPost req:
        let form  = decodedQuery req.body
        echo form
        # form["username"]
        # form["password"]

      else:
        req.respond 200, emptyHttpHeaders(), signinPageHtml()


    proc apiHomePage(req) =
      req.respond 200, emptyHttpHeaders(), "hey"

    proc signinApi(req) =
      discard

    # get    "/users/",                 listUsersPage
    # get    "/user/",                  userInfoPage
    # get    "/profile/",               profileDispatcher


  proc initRouter: Router = 
    with result:
      get    "/",                        indexPage
      get    "/api/",                    apiHomePage
      get    "/static/**",               staticFilesServ

      post   "/api/sign-in/",            signinApi

      post   "/sign-out/",               signoutPage

      get    "/sign-in/",                signinPage
      post   "/sign-in/",                signinPage

      get    "/sign-up/",                signupPage
      post   "/sign-up/",                signupPage
      
      
      # get    "/docs/",                signupPage
      
      # get    "/users/",                 listUsersPage
      # get    "/user/",                  userInfoPage
      # get    "/profile/",               profileDispatcher

      # post   "/api/database/",            initDB
      # get    "/api/databases/",         
      # delete "/api/database/",            delete database
      # get    "/api/database/blueprint/",  gqlService
      # post   "/api/database/blueprint/",  gqlService
      # post   "/api/database/validate/",   validate database based on blueprint
      # get    "/api/database/stats/",      stats
      # get    "/api/database/backups/",    backup

      post   "/api/database/query/",      askQueryApi
      get    "/api/database/node/",       getNodeApi
      get    "/api/database/edge/",       getEdgeApi
      post   "/api/database/nodes/",      insertNodesApi
      post   "/api/database/edges/",      insertEdgesApi
      put    "/api/database/nodes/",      updateNodesApi
      put    "/api/database/nodes/",      updateEdgesApi
      delete "/api/database/nodes/",      deleteNodesApi
      delete "/api/database/edges/",      deleteEdgesApi

      # get    "/api/database/indexes/",  gqlService
      # post   "/api/database/index/",    gqlService
      # delete "/api/database/index/",    gqlService


  app.server                 = newServer initRouter()
  app.defaultQueryStrategies = parseQueryStrategies extractStrategies parseTomlFile config.queryStrategyFile
  app

proc run(app: App) = 
  echo fmt"running in {app.config.url}"
  serve app.server, app.config.server.port, app.config.server.host.string


when isMainModule:
  let
    cmdParams = toParamTable commandLineParams()
    confPath  = cmdParams.getOrDefault("", "./config.toml")

  echo "config file path: ", confPath

  let
    ctx  = AppContext(
      cmdParams: cmdParams,
      tomlConf:  parseTomlFile confPath)
    conf = buildConfig ctx
    app  = initApp     conf

  if conf.logs.config:
    echo conf[]

  run app
