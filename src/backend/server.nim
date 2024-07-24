import std/[strutils, strformat, tables, json, monotimes, os, times, with, sugar, uri, mimetypes, paths, oids, math, sequtils]

import db_connector/db_sqlite
import mummy, mummy/routers
import webby
import parsetoml
import cookiejar
# TODO use waterpark

import ../query_language/[parser, core]
import ../utils/other
import ../bridge
import routes
import ./[model, view, config]


type
  App* = object
    server*: Server
    config*: AppConfig
    defaultQueryStrategies*: QueryStrategies

using 
  req: Request


func userDbFileName(uname, dbname: string): string = 
  fmt"user-{uname}-db-{dbname}.db.sqlite3"

func userDbPath(app: App, uname, dbname: string): Path = 
  app.config.storage.usersDbDir / userDbFileName(uname, dbname).Path


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


proc initDB(fpath: Path) = 
  initDbSchema openSqliteDB fpath

proc prepareDB(fpath: Path) = 
  if not fileExists fpath: 
    initDB fpath

proc preapreStorage(config: AppConfig) = 
  discard existsOrCreateDir config.storage.appDbFile.string.splitPath.head
  discard existsOrCreateDir config.storage.usersDbDir.string
  discard existsOrCreateDir config.storage.backupdir.string

  prepareDB config.storage.appDbFile

proc initApp(config: AppConfig): App = 
  preapreStorage config

  var app = App(config: config)

  proc getDB: DbConn = 
    openSqliteDB app.config.storage.appDbFile

  template logBody: untyped =
    if app.config.logs.reqbody:
      echo req.body

  template logSql(q): untyped =
    if app.config.logs.sql:
      echo q

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
          req.respond 200, jsonHeader(), askQueryDbRaw(
            db, s => $j["context"][s], 
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
        let val   = getEntityDbRaw(db, id, ent)
        
      # XXX logSql
      req.respond 200, jsonHeader(), val

    proc getNodeApi(req) = getEntity req, nodes
    proc getEdgeApi(req) = getEntity req, edges


    proc insertNodesApi(req) = 
      let j = parseJson req.body
      withDB:
        let ids = collect:
          for n in j:
            insertNodeDB db, parseTag getstr n["tag"], n["doc"]

      req.respond 200, jsonHeader(), jsonAffectedRows(len ids, ids)

    proc insertEdgesApi(req) = 
      let j = parseJson req.body
      withDB:
        let ids = collect:
          for n in j:
            insertEdgeDB db, parseTag getstr n["tag"], n["doc"], getInt n["source"], getInt n["target"]

      req.respond 200, jsonHeader(), jsonAffectedRows(len ids, ids)


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


    proc apiHome(req) =
      req.respond 200, emptyHttpHeaders(), $ %*{
        "status": "running",
      }

    proc signinApi(req) =
      discard

    # ------------------------

    proc staticFilesServ(req) =
      let
        fname   = "./assets/" & req.uri.splitPath.tail
        ext     = fname.splitFile.ext.strip(chars= {'.'}, trailing = false)
        content = readfile fname

      req.respond 200, toWebby @{"Content-Type": getMimetype ext} , content

    proc indexPage(req) =
      req.respond 200, emptyHttpHeaders(), landingPageHtml()

    proc docsPage(req) = 
      req.respond 200, emptyHttpHeaders(), docsPageHtml()


    const authKey = "auth"

    proc signInImpl(req; uid: Id, uname: string) =
      let token = $genOid()
      withDb:
        let 
          aid = insertNodeDB(db, parseTag "#auth",     %token)
          rid = insertEdgeDB(db, parseTag "#auth_for", newJNull(), aid, uid)
      
      req.respond 200, toWebby @{"Set-Cookie": fmt"{authKey}={token}"} , redirectingHtml profile_url uname

    proc signupPage(req) =
      if isPost req:
        let 
          form  = decodedQuery req.body
          uname = form["username"]
          passw = form["password"]

        withDB:
          let ans = ignore askQueryDB(db, s => $(%uname), 
            parseSpQl get_user_by_name, 
            app.defaultQueryStrategies)

          case ans["result"].len
          of 0:
            let uid = insertNodeDB(db, userTag, initUserDoc(uname, passw, false))
            signInImpl req, uid, uname
          else:
            req.respond 200, emptyHttpHeaders(), signupPageHtml @["duplicated username"]

      else:
        req.respond 200, emptyHttpHeaders(), signupPageHtml(@[])

    proc signinPage(req) =
      if isPost req:
        let 
          form  = decodedQuery req.body
          uname = form["username"]
          passw = form["password"]
          ctx   = %*{"uname": uname}

        withDB:
          let ans = askQueryDB(
            db, s => $ctx[s], 
            parseSpQl get_user_by_name, app.defaultQueryStrategies)

          case ans["result"].len
          of 0:
            req.respond 200, emptyHttpHeaders(), signinPageHtml(@["no such user"])

          else:
            let u = ans["result"][0]
            if u[docCol]["pass"].getStr == passw:
              signInImpl req, getInt u[idCol], uname
            else:
              req.respond 200, emptyHttpHeaders(), signinPageHtml(@["pass wrong"])
            
      else:
        req.respond 200, emptyHttpHeaders(), signinPageHtml(@[])

    proc signOutCookieSet: webby.HttpHeaders =
      result["Set-Cookie"] = $initCookie(authKey, "", path = "/")

    proc signoutPage(req) =
      req.respond 200, signOutCookieSet(), redirectingHtml "/sign-in/"


    proc listUsersPage(req) = 
      withDB:
        let users = askQueryDb(db, s => "", parseSpQl all_users, app.defaultQueryStrategies)
      req.respond 200, emptyHttpHeaders(), userslistPageHtml users["result"].getElems

    proc userProfilePage(req) =
      var  uname = 
        if isPost req: ""
        else:          req.queryParams["u"]

      if isPost req:
        let 
          form = decodedQuery req.body

        if   "add-database"    in form:
          let 
            dbname = form["database-name"]
            uname  = form["username"] 
          
          prepareDB app.userDbPath(uname, dbname)

          withDB:
            let
              userDoc = db.askQueryDB(_ => $ %uname, parseSpql get_user_by_name, app.defaultQueryStrategies)
              uid = userDoc["result"][0][idCol].getInt
              did = db.insertNodeDB(dbTag,   initDbDoc dbname)
              oid = db.insertEdgeDB(ownsTag, newJNull(), uid, did)

            req.respond 200, emptyHttpHeaders(), redirectingHtml profile_url(uname)

        elif "change-password" in form:
          discard

        else:
          # invalid
          discard
        
      else:
        withDb:
          let dbs = db.askQueryDB(
              _ => $ %uname, 
              parseSpQl dbs_of_user, 
              app.defaultQueryStrategies)["result"].getElems

          var 
            sizes, lastModifs: seq[int]

          for doc in dbs:
            let
              dbname = getstr doc[docCol]["name"] 
              p = string userDbPath(app, uname, dbname)

            add sizes,      int    getFileSize p
            add lastModifs, toUnix getLastModificationTime p

        req.respond(200, 
          signOutCookieSet(), 
          profilePageHtml(uname, dbs, sizes, lastModifs))

    proc databasePage(req) = 
      let 
        uname  = req.queryParams["u"]
        dbname = req.queryParams["db"]
        path   = string userDbPath(app, uname, dbname)

      withDb:
        let 
          cnodes = db.countEntitiesDB nodes
          cedges = db.countEntitiesDB edges
          
          ln     = cnodes.len
          le     = cedges.len

          dn     = sum cnodes.mapit(it.count)
          de     = sum cedges.mapit(it.count)
      

      req.respond 200, emptyHttpHeaders(), databasePageHtml(
        uname, 
        dbname, 
        int getFileSize path,
        toUnix getLastModificationTime path,
        cnodes, cedges,
        ln, le,
        dn, de)


    proc databaseDownload(req) = 
      let 
        uname  = req.queryParams["u"]
        dbname = req.queryParams["db"]

      req.respond(200, 
        toWebby @{
          "Content-Type": "application/octet-stream",
          "Content-Disposition": fmt "attachment; filename=\"{dbname}.db.sqlite3\"",
        }, 
        readfile string app.userDbPath(uname, dbname))


    proc databaseBackup(req) = 
      let 
        uname  = req.queryParams["u"]
        dbname = req.queryParams["db"]

    proc databaseRemove(req) = 
      let 
        uname  = req.queryParams["u"]
        dbname = req.queryParams["db"]


  proc initRouter: Router = 
    with result:
      get    br"landing",                indexPage
      get    br"static-files",           staticFilesServ
      get    br"docs",                   docsPage

      get    br"sign-up",                signupPage
      post   br"sign-up",                signupPage
      post   br"sign-in-api",            signinApi
      get    br"sign-in",                signinPage
      post   br"sign-in",                signinPage
      get    br"sign-out",               signoutPage
      
      get    br"users-list",             listUsersPage
      get    br"profile",                userProfilePage
      post   br"profile",                userProfilePage

      get    br"database",               databasePage 
      post   br"database",               databasePage 
      get    br"database-download",      databaseDownload

      get     br"api-home",              apiHome
      post    br"api-query-database",    askQueryApi
      get     br"api-get-node-by-id",    getNodeApi
      get     br"api-get-edge-by-id",    getEdgeApi
      post    br"api-insert-nodes",      insertNodesApi
      post    br"api-insert-edges",      insertEdgesApi
      put     br"api-update-nodes",      updateNodesApi
      put     br"api-update-edges",      updateEdgesApi
      delete  br"api-delete-nodes",      deleteNodesApi
      delete  br"api-delete-edges",      deleteEdgesApi
      
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
