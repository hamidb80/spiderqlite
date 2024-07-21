import std/[strutils, strformat, tables, json, monotimes, os, times, with, sugar, uri, mimetypes]

import db_connector/db_sqlite
import mummy, mummy/routers
import webby
import parsetoml
import cookiejar
# TODO use waterpark

import gql/[parser, core, queries]
import ./view
import ./utils/other
import ./config


type
  App* = object
    server*: Server
    config*: AppConfig
    defaultQueryStrategies*: QueryStrategies



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


func isPost(req: Request): bool = 
  req.httpmethod == "POST"

func jsonToSql(j: JsonNode): string = 
  case j.kind
  of JInt:    $j.getInt
  of JFloat:  $j.getFloat
  of JNull:   "NULL"
  of JString: dbQuote getStr j
  of JBool:   $j.getBool
  else: 
    raisee "invalid json kind: " & $j.kind


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

  template withDb(body): untyped =
    let 
      # dbName        = req.queryparams["db"]
      dbName        = app.config.storage.appDbFile
      db {.inject.} = openSqliteDB dbName
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
    proc askQueryApi(req: Request) {.gcsafe.} =
      try:
        logBody()

        let 
          thead           = getMonoTime()
          j               = parseJson req.body
          ctx             = j["context"]
          tparsejson      = getMonoTime()
          gql             = parseGql  getstr  j["query"]
          tparseq         = getMonoTime()
          sql             = toSql(
            gql, 
            app.defaultQueryStrategies, 
            s => $ctx[s])
          tquery          = getMonoTime()

        logSql sql

        var 
          rows = 0
          acc = newStringOfCap 1024 * 100 # 100 KB

        withDb:
          acc.add "{\"result\": ["

          for row in db.fastRows sql:
            inc rows
            let r   = row[0]

            if r[0] in {'[', '{'} or (r.len < 20 and isNumber r):
              acc.add r
            else:
              acc.add escapeJson r

            acc.add ','

          if acc[^1] == ',': # check for 0 results
            acc.less
          
          acc.add ']'

        let tcollect = getMonoTime()

        with acc:
          add ','
          add "\"length\":"
          add $rows
          add ','
          add "\"performance\":{"
          add "\"unit\": \"us\""
          add ','
          add "\"total\":"
          add $inMicroseconds(tcollect - thead)
          add ','
          add "\"parse body\":"
          add $inMicroseconds(tparsejson - thead)
          add ','
          add "\"parse query\":"
          add $inMicroseconds(tparseq - tparsejson)
          add ','
          add "\"query matching & conversion\":"
          add $inMicroseconds(tquery - tparseq)
          add ','
          add "\"exec & collect\":"
          add $inMicroseconds(tcollect - tquery)
          add '}'
          add '}'

        req.respond 200, jsonHeader(), acc
        echo inMicroseconds(tcollect - thead), "us"

      except:
        let 
          e  = getCurrentException()
          me = getCurrentExceptionMsg()
          je = jsonError(me, e.getStackTrace())
        req.respond 400, jsonHeader(), je
        echo "did error ", je


    proc getEntity(req: Request, ent: Entity) =
      logPerf:
        let
          id    = parseInt        req.queryParams["id"]
          q     = prepareGetQuery ent

        withDB:
          let row = getRow(db, q, id)
        
        logSql q
        req.respond 200, jsonHeader(), row[0]

    proc getNodeApi(req: Request) =
      getEntity req, nodes

    proc getEdgeApi(req: Request) =
      getEntity req, edges


    proc insertNodesApi(req: Request) =
      logPerf:
        logBody()

        let
          j      = parseJson req.body
          q      = prepareNodeInsertQuery()

        logSql q
        withDB:
          var ids: seq[int]
          for a in j:
            let
              tag    = parseTag getstr a["tag"]
              doc    =                $a["doc"]
              id     = db.insertID(q, tag, doc)
            ids.add id

        req.respond 200, jsonHeader(), jsonAffectedRows(len ids, ids)

    proc insertEdgesApi(req: Request) =
      logPerf:
        logBody()

        let
          j      = parseJson req.body
          q      = prepareEdgeInsertQuery()
        
        logSql q
        withDB:
          var ids: seq[int]
          for a in j:
            let
              tag    = parseTag getstr a["tag"]
              source =          getInt a["source"]
              target =          getInt a["target"]
              doc    =                $a["doc"]
              id     = db.insertID(q, tag, source, target, doc)
            
            ids.add id

        req.respond 200, jsonHeader(), jsonAffectedRows(len ids, ids)


    proc updateEntity(req: Request, ent: Entity) =
      logPerf:
        logBody()

        let
          j   = parseJson req.body
          q   = prepareUpdateQuery ent

        logSql q

        if j.kind == JObject:

          withDB:

            var acc: seq[int]
            for k, v in j:
              let 
                id       = parseint k
                doc      = $v
                affected = db.execAffectedRows(q, doc, id)

              if affected == 1:
                acc.add id

          req.respond 200, jsonHeader(), jsonAffectedRows(acc.len, acc)
        
        else:
          raisee "invalid json object for update. it should be object of {id => new_doc}"

    proc updateNodesApi(req: Request) =
      updateEntity req, nodes

    proc updateEdgesApi(req: Request) =
      updateEntity req, edges


    proc deleteEntity(req: Request, ent: Entity) =
      logPerf:
        logBody()

        let
          j        = parseJson req.body
          ids      = j["ids"].to seq[int]
          q        = prepareDeleteQuery(ent, ids)

        logSql q
        withDB:
          let affected = db.execAffectedRows q
        req.respond 200, jsonHeader(), jsonAffectedRows affected

    proc deleteNodesApi(req: Request) =
      deleteEntity req, nodes

    proc deleteEdgesApi(req: Request) =
      deleteEntity req, edges


    proc staticFilesServ(req: Request) =
      let
        fname   = "./assets/" & req.uri.splitPath.tail
        ext     = fname.splitFile.ext.strip(chars= {'.'}, trailing = false)
        content = readfile fname

      req.respond 200, toWebby @{"Content-Type": getMimetype ext} , content

    proc indexPage(req: Request) =
      req.respond 200, emptyHttpHeaders(), landingPageHtml()

    proc signupPage(req: Request) =
      req.respond 200, emptyHttpHeaders(), signinPageHtml()


    const authKey = "auth"

    proc signOutCookieSet: webby.HttpHeaders =
      result["Set-Cookie"] = $initCookie(authKey, "", path = "/")

    proc signoutPage(req: Request) =
      req.respond 200, signOutCookieSet(), "redirecting to ... XXX"

    # proc signin


    proc signinPage(req: Request) =
      if isPost req:
        let form  = decodedQuery req.body
        echo form
        # form["username"]
        # form["password"]

      else:
        req.respond 200, emptyHttpHeaders(), signinPageHtml()


    proc apiHomePage(req: Request) =
      req.respond 200, emptyHttpHeaders(), "hey"

    proc signinApi(req: Request) =
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
