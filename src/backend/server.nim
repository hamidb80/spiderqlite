import std/[strutils, strformat, tables, json, monotimes, os, times, with, sugar, uri, mimetypes, paths, oids, math, sequtils, times]

import std/[browsers, monotimes]

import db_connector/db_sqlite
import mummy, mummy/routers
import webby
import parsetoml
import cookiejar
# TODO use waterpark
# import pretty

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
  app: App

const authKey = "auth"


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


func getJsType(j: JsonNode, depth = 0): JsonNode = 
  case j.kind
  of JNull: newJNull()
  of JBool: %"boolean"
  of JInt: %"int"
  of JFloat: %"float"
  of JString: %"string"
  of JArray: 
    var arr = newjarray() 
    if j.len != 0:
      add arr, getJsType j[0]
    arr
  
  of JObject: 
    var obj = newJObject()

    for k, v in j:
      obj[k] = getJsType v

    obj


func extractStrategies*(tv: TomlValueRef): seq[TomlValueRef] = 
  getElems tv["strategies"]


func extractVisEdges(queryResult: JsonNode): tuple[nodeIds, edgeIds: seq[int]] =
  for arr in queryResult:
    add result.nodeIds, arr[1].getint
    add result.nodeIds, arr[2].getint
    add result.edgeIds, arr[0].getint  

func canBeVisualized(queryResult: JsonNode, depth=0): bool =
  case queryResult.kind
  of JArray: 
    for i in queryResult:
      if not canBeVisualized(i, depth+1):
        return false
    true
  of Jint:   depth != 0
  else:      false


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


template logBody: untyped =
  if app.config.logs.reqbody:
    echo req.body

template logSql(q): untyped =
  if app.config.logs.sql:
    echo q

proc getDB(config: AppConfig): DbConn = 
  openSqliteDB config.storage.appDbFile

template withDb(app, body): untyped =
  # TODO error handling
  let db {.inject.} = getDB(app.config)
  body
  close db
  
template logPerf(body): untyped =
  let thead = getMonoTime()
  body
  let ttail = getMonoTime()
  if app.config.logs.performance:
    let tdelta = ttail - thead
    echo inMicroseconds tdelta, "us"

# Controllers ------------------------------------

proc apiAskQuery(req; app) =
  try:
    let j = parseJson req.body
    withdb app:
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

proc getEntity(req; app; ent: Entity) =
  let id    = parseInt   req.queryParams["id"]
  withDB app:
    let val   = getEntityDbRaw(db, id, ent)
    
  # XXX logSql
  req.respond 200, jsonHeader(), val

proc apiGetNode(req, app) = 
  getEntity req, app, nodes

proc apiGetEdge(req, app) = 
  getEntity req, app, edges

proc apiInsertNodes(req; app) = 
  let j = parseJson req.body
  withDB app:
    let ids = collect:
      for n in j:
        insertNodeDB db, parseTag getstr n["tag"], n["doc"]

  req.respond 200, jsonHeader(), jsonAffectedRows(len ids, ids)

proc apiInsertEdges(req; app) = 
  let j = parseJson req.body
  withDB app:
    let ids = collect:
      for n in j:
        insertEdgeDB(db, 
          parseTag getstr n["tag"], 
                          n["doc"], 
          getInt          n["source"], 
          getInt          n["target"])

  req.respond 200, jsonHeader(), jsonAffectedRows(len ids, ids)


proc updateEntity(req; app; ent: Entity) =
  let j = parseJson req.body
  # logSql q

  case j.kind
  of JObject:
    withDB app:
      var acc: seq[int]
      for key, doc in j:
        let id = parseInt key
        if updateEntityDocDB(db, ent, id, doc):
          add acc, id

    req.respond 200, jsonHeader(), jsonAffectedRows(len acc, acc)
  
  else:
    raisee "invalid json object for update. it should be object of {id => new_doc}"

proc apiupdateNodes(req; app) = 
  updateEntity req, app, nodes

proc apiupdateEdges(req; app) = 
  updateEntity req, app, edges


proc deleteEntity(req; app; ent: Entity) =
  let
    j        = parseJson req.body
    ids      = j["ids"].to seq[int]
  withDB app:
    let affected = deleteEntitiesDB(db, ent, ids)
  req.respond 200, jsonHeader(), jsonAffectedRows affected

proc apiDeleteNodes(req; app) = 
  deleteEntity req, app, nodes

proc apiDeleteEdges(req; app) = 
  deleteEntity req, app, edges


proc apiHome(req; app) =
  req.respond 200, emptyHttpHeaders(), $ %*{
    "status": "ok",
  }

proc apiSignin(req; app) =
  discard

# ------------------------

proc FilesStaticServ(req; app) =
  let
    fname   = "./assets/" & req.uri.splitPath.tail
    ext     = fname.splitFile.ext.strip(chars= {'.'}, trailing = false)
    content = readfile fname

  req.respond 200, toWebby @{"Content-Type": getMimetype ext} , content

proc pageIndex(req; app) =
  req.respond 200, emptyHttpHeaders(), landingPageHtml()

proc pageDocs(req; app) = 
  req.respond 200, emptyHttpHeaders(), docsPageHtml()


proc signInImpl(req; app; uid: Id, uname: string) =
  let token = $genOid()
  withDb app:
    let 
      aid = insertNodeDB(db, parseTag "#auth",     %token)
      rid = insertEdgeDB(db, parseTag "#auth_for", newJNull(), aid, uid)
  
  req.respond 200, toWebby @{"Set-Cookie": fmt"{authKey}={token}"} , redirectingHtml profile_url uname

proc pageSignup(req; app) =
  if isPost req:
    let 
      form  = decodedQuery req.body
      uname = form["username"]
      passw = form["password"]

    withDB app:
      let ans = ignore askQueryDB(db, s => $(%uname), 
        parseSpQl get_user_by_name, 
        app.defaultQueryStrategies)

      case ans["result"].len
      of 0:
        let uid = insertNodeDB(db, userTag, initUserDoc(uname, passw, false))
        signInImpl req, app, uid, uname
      else:
        req.respond 200, emptyHttpHeaders(), signupPageHtml @["duplicated username"]

  else:
    req.respond 200, emptyHttpHeaders(), signupPageHtml(@[])

proc pageSignin(req; app) =
  if isPost req:
    let 
      form  = decodedQuery req.body
      uname = form["username"]
      passw = form["password"]
      ctx   = %*{"uname": uname}

    withDB app:
      let ans = askQueryDB(
        db, s => $ctx[s], 
        parseSpQl get_user_by_name, app.defaultQueryStrategies)

      case ans["result"].len
      of 0:
        req.respond 401, emptyHttpHeaders(), signinPageHtml(@["no such user"])

      else:
        let u = ans["result"][0]
        if u[docCol]["pass"].getStr == passw:
          signInImpl req, app, getInt u[idCol], uname
        else:
          req.respond 200, emptyHttpHeaders(), signinPageHtml(@["pass wrong"])
        
  else:
    req.respond 200, emptyHttpHeaders(), signinPageHtml(@[])

proc signOutCookieSet: webby.HttpHeaders =
  result["Set-Cookie"] = $initCookie(authKey, "", path = "/")

proc pageSignout(req; app) =
  req.respond 200, signOutCookieSet(), redirectingHtml "/sign-in/"


proc listUsersPage(req; app) = 
  withDB app:
    let users = askQueryDb(db, s => "", parseSpQl all_users, app.defaultQueryStrategies)
  req.respond 200, emptyHttpHeaders(), userslistPageHtml users["result"].getElems

proc pageUserProfile(req; app) =
  let uname = req.queryParams["u"]

  if isPost req:
    let form = decodedQuery req.body

    if   "add-database"    in form:
      let dbname = form["database-name"]
      prepareDB app.userDbPath(uname, dbname)

      withDB app:
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
    withDb app:
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

proc pageDatabase(req; app) = 
  let 
    uname  = req.queryParams["u"]
    dbname = req.queryParams["db"]
    path   = string userDbPath(app, uname, dbname)

  withDb app: # XXX use user's db not app.db !!
    var
      cnodes = countEntitiesDB(db, nodes)
      cedges = countEntitiesDB(db, edges)
      
      ln     = cnodes.len
      le     = cedges.len

      dn     = sum cnodes.mapit(it.count)
      de     = sum cedges.mapit(it.count)

      queryReuslts, nodesGroup, edgesGroup: JsonNode = newJNull()
      
      whatSelected = "nothing"
      selectedData = newJNull()
      selectedId   = 0
      perf         = 0

    for n in cnodes.mitems:
      n[2] = getJsType n[2]

    for e in cedges.mitems:
      e[2] = getJsType e[2]
    

    if isPost req:
      let form = decodedQuery req.body
      
      if "edge-id" in form:
        whatSelected = "edge"
        selectedId   = parseInt form["edge-id"]
        selectedData = db.getEdgeDB(selectedId)

      elif "node-id" in form:
        whatSelected = "node"
        selectedId   = parseInt form["node-id"]
        selectedData = db.getNodeDB(selectedId)


      if "ask" in form:
        let 
          head = getMonoTime()
          c    = form["spql_query"]
          spql = parseSpql c

        queryReuslts = db.askQueryDB(
            _ => "\"???\"", 
            spql, 
            app.defaultQueryStrategies)["result"]

        perf  = (getMonoTime() - head).inMicroseconds

        if canBeVisualized queryReuslts:
          let (nodeids, edgeids) = extractVisEdges queryReuslts
          nodesGroup = db.getNodesDB(nodeids)
          edgesGroup = db.getEdgesDB(edgeids)

  req.respond 200, emptyHttpHeaders(), databasePageHtml(
    uname, 
    dbname, 
    int getFileSize path,
    toUnix getLastModificationTime path,
    cnodes, cedges,
    ln, le,
    dn, de,
    queryReuslts, nodesGroup, edgesGroup,
    whatSelected, selectedData,
    perf) 

proc filesDatabaseDownload(req; app) = 
  let 
    uname  = req.queryParams["u"]
    dbname = req.queryParams["db"]

  req.respond(200, 
    toWebby @{
      "Content-Type": "application/octet-stream",
      "Content-Disposition": fmt "attachment; filename=\"{dbname}.db.sqlite3\"",
    }, 
    readfile string app.userDbPath(uname, dbname))

# APP INIT -------------------------------------

proc initApp(config: AppConfig): App = 
  preapreStorage config

  var app = App(config: config)

  proc initRouter: Router = 
    
    template rr(fn): untyped = 
      proc (req: Request): void = 
        fn(req, app)

    if config.frontend.enabled:
      get    result,    br"landing",               rr pageIndex
      get    result,    br"static-files",          rr FilesStaticServ
      get    result,    br"docs",                  rr pageDocs

      get    result,    br"sign-up",               rr pageSignup
      post   result,    br"sign-up",               rr pageSignup
      get    result,    br"sign-in",               rr pageSignin
      post   result,    br"sign-in",               rr pageSignin
      get    result,    br"sign-out",              rr pageSignout
      
      get    result,    br"users-list",            rr listUsersPage
      get    result,    br"profile",               rr pageUserProfile
      post   result,    br"profile",               rr pageUserProfile

      get    result,    br"database",              rr pageDatabase 
      post   result,    br"database",              rr pageDatabase 
      get    result,    br"database-download",     rr filesDatabaseDownload

    get      result,    br"api-home",              rr apiHome
    post     result,    br"sign-in-api",           rr apiSignin
    post     result,    br"api-query-database",    rr apiAskQuery
    get      result,    br"api-get-node-by-id",    rr apiGetNode
    get      result,    br"api-get-edge-by-id",    rr apiGetEdge
    post     result,    br"api-insert-nodes",      rr apiInsertNodes
    post     result,    br"api-insert-edges",      rr apiInsertEdges
    put      result,    br"api-update-nodes",      rr apiupdateNodes
    put      result,    br"api-update-edges",      rr apiupdateEdges
    delete   result,    br"api-delete-nodes",      rr apiDeleteNodes
    delete   result,    br"api-delete-edges",      rr apiDeleteEdges
    
    # get    "/api/database/indexes/",  gqlService
    # post   "/api/database/index/",    gqlService
    # delete "/api/database/index/",    gqlService

  app.server                 = newServer initRouter()
  app.defaultQueryStrategies = parseQueryStrategies extractStrategies parseTomlFile config.queryStrategyFile
  app

proc run(app: App) = 
  echo fmt"running in {app.config.url}"
  serve app.server, app.config.server.port, app.config.server.host.string

# GO -------------------------------------------

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

  if conf.frontend.enabled and conf.open_browser:
    openDefaultBrowser app.config.url

  run app
