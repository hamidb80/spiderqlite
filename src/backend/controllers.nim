import std/[strformat, paths, mimetypes, json, tables, uri, sugar, strutils, os, times, monotimes, math, sequtils, options]


import ../query_language/[parser, core]
import ../utils/other
import ../bridge
import routes
import ./[model, config, view]


import db_connector/db_sqlite
import mummy, mummy/routers
import webby
import parsetoml
import cookiejar

# TODO use waterpark
# import pretty

using 
  req: Request
  app: App
  ctx: ViewCtx


const JWT_AUTH_COOKIE = "auth"


func userDbFileName(uname, dbname: string): string = 
  fmt"user-{uname}-db-{dbname}.db.sqlite3"

func userDbPath(app; uname, dbname: string): Path = 
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
  of JNull:   newJNull()
  of JBool:   %"boolean"
  of JInt:    %"int"
  of JFloat:  %"float"
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

proc apiAskQuery*(req; app;) =
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

proc apiGetNode*(req: Request, app: App) = 
  getEntity req, app, nodes

proc apiGetEdge*(req: Request, app: App) = 
  getEntity req, app, edges

proc apiInsertNodes*(req; app;) = 
  let j = parseJson req.body
  withDB app:
    let ids = collect:
      for n in j:
        insertNodeDB db, parseTag getstr n["tag"], n["doc"]

  req.respond 200, jsonHeader(), jsonAffectedRows(len ids, ids)

proc apiInsertEdges*(req; app;) = 
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

proc apiupdateNodes*(req; app;) = 
  updateEntity req, app, nodes

proc apiupdateEdges*(req; app;) = 
  updateEntity req, app, edges


proc deleteEntity(req; app; ent: Entity) =
  let
    j        = parseJson req.body
    ids      = j["ids"].to seq[int]
  withDB app:
    let affected = deleteEntitiesDB(db, ent, ids)
  req.respond 200, jsonHeader(), jsonAffectedRows affected

proc apiDeleteNodes*(req; app;) = 
  deleteEntity req, app, nodes

proc apiDeleteEdges*(req; app;) = 
  deleteEntity req, app, edges


proc apiHome*(req; app;) =
  req.respond 200, emptyHttpHeaders(), $ %*{
    "status": "ok",
  }

proc apiSignin*(req; app;) =
  discard

# ------------------------

proc filesStaticServ*(req; app) =
  let
    fname   = "./assets/" & req.uri.splitPath.tail
    ext     = fname.splitFile.ext.strip(chars= {'.'}, trailing = false)
    content = readfile fname

  req.respond 200, toWebby @{"Content-Type": getMimetype ext} , content


import jwt
const JWT_SECRET = "1234"
const JWT_ALGO = "HS256"
const JWT_DATA_KEY = "dat"


proc verifyJWT(token: string): bool =
  try:
    let jwtToken = token.toJWT()
    result = jwtToken.verify(JWT_SECRET, HS256)
  except InvalidToken:
    result = false

proc decodeJWT(token: string): JsonNode =
  token.toJWT.claims[JWT_DATA_KEY].node

proc signJWT(data: JsonNode): string =
  var token = toJWT(%*{
    "header": {
      "alg": JWT_ALGO,
      "typ": "JWT"
    },
    "claims": {
      JWT_DATA_KEY: data,
      "exp": (getTime() + 1.days).toUnix()
    }
  })

  token.sign(JWT_SECRET)
  $token


proc cookies(req): CookieJar = 
  result = initCookieJar()
  parse result, req.headers["Cookie"]

proc ctx(req): ViewCtx = 
  let token = req.cookies[JWT_AUTH_COOKIE]
  if verifyJWT token:
    result.username = some getStr token.decodeJWT["username"]
  else:
    discard

proc pageIndex*(req; app) =
  req.respond 200, emptyHttpHeaders(), landingPageHtml(req.ctx)

proc pageDocs*(req; app) = 
  req.respond 200, emptyHttpHeaders(), docsPageHtml(req.ctx)

proc signInImpl(req; app; uid: Id, uname: string) =
  let jwtoken = signJwt %*{"1": 1}


  req.respond 200, toWebby @{"Set-Cookie": fmt"{JWT_AUTH_COOKIE}={jwtoken}"} , redirectingHtml(profile_url uname)

proc pageSignin*(req; app) =
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

      case len ans["result"]
      of 0:
        req.respond 401, emptyHttpHeaders(), signinPageHtml(req.ctx, @["no such user"])

      of 1:
        let u = ans["result"][0]
        if u[docCol]["pass"].getStr == passw:
          signInImpl req, app, getInt u[idCol], uname
        else:
          req.respond 200, emptyHttpHeaders(), signinPageHtml(req.ctx, @["pass wrong"])

      else:
        req.respond 500, emptyHttpHeaders(), signinPageHtml(req.ctx, @["internal error"])

  else:
    req.respond 200, emptyHttpHeaders(), signinPageHtml(req.ctx, @[])

proc pageSignup*(req; app) =
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
        req.respond 200, emptyHttpHeaders(), signupPageHtml(req.ctx, @["duplicated username"])

  else:
    req.respond 200, emptyHttpHeaders(), signupPageHtml(req.ctx, @[])

proc signOutCookieSet: webby.HttpHeaders =
  result["Set-Cookie"] = $initCookie(JWT_AUTH_COOKIE, "", path = "/")

proc pageSignout*(req; app) =
  req.respond 200, signOutCookieSet(), redirectingHtml( "/sign-in/")


proc pageListUsers*(req; app) = 
  withDB app:
    let users = askQueryDb(db, s => "", parseSpQl all_users, app.defaultQueryStrategies)
  req.respond 200, emptyHttpHeaders(), userslistPageHtml(req.ctx, users["result"].getElems)

proc pageUserProfile*(req; app) =
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
          # oid = db.insertEdgeDB(ownsTag, newJNull(), uid, did)

        req.respond 200, emptyHttpHeaders(), redirectingHtml( profile_url(uname))

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
      profilePageHtml(req.ctx, uname, dbs, sizes, lastModifs))

proc pageDatabase*(req; app) = 
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
    req.ctx,
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

proc filesDatabaseDownload*(req; app) = 
  let 
    uname  = req.queryParams["u"]
    dbname = req.queryParams["db"]

  req.respond(200, 
    toWebby @{
      "Content-Type": "application/octet-stream",
      "Content-Disposition": fmt "attachment; filename=\"{dbname}.db.sqlite3\"",
    }, 
    readfile string app.userDbPath(uname, dbname))
