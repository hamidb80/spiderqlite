import std/[strutils, strformat, json, monotimes, times, with, sugar]

import db_connector/db_sqlite
import mummy, mummy/routers
import webby

import gql
import ./utils/other
import ./config


type
  App* = object
    server*: Server
    config*: AppConfig
    defaultQueryStrategies*: QueryStrategies


func jsonAffectedRows(n: int, ids: seq[int] = @[]): string = 
  "{\"affected_rows\":" & $n & ", \"ids\": [" & ids.joinComma & "]}"

func jsonHeader: HttpHeaders = 
  toWebby @{"Content-Type": "application/json"}

func jsonIds(ids: seq[int]): string = 
  "{\"ids\": [" & ids.joinComma & "]}"

func jsonError(msg: string): string = 
  "{\"error\": {\"message\": " & msg.escapeJson & "}}"


proc initApp(ctx: AppContext, config: AppConfig): App = 
  var app: App

  template logSql(q): untyped =
    if app.config.logs.sql:
      echo q

  # TODO open & close db
  template withDb(dbpath, body): untyped =
    discard
    
  # TODO echo time spent
  template logPerf(body): untyped =
    discard
    

  unwrap controllers:
    proc indexPage(req: Request) =
      req.respond 200, jsonHeader(), "hey! use APIs for now!"

    proc staticFiles(req: Request) =
      discard

      
    proc askQuery(req: Request) {.gcsafe.} =
      try:
        let 
          thead           = getMonoTime()
          j               = parseJson req.body
          ctx             = j["context"]

        debugEcho j.pretty
        debugEcho getstr j["query"]

        let
          tparsejson      = getMonoTime()
          gql             = parseGql  getstr  j["query"]
          tparseq         = getMonoTime()
          db              = openSqliteDB  app.config.storage.appDbFile
          topenDb         = getMonoTime()
          sql             = toSql(
            gql, 
            app.defaultQueryStrategies, 
            s => $ctx[s])
          tquery          = getMonoTime()

        logSql sql

        var rows = 0
        var acc = newStringOfCap 1024 * 100 # 100 KB
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
          add "\"openning db\":"
          add $inMicroseconds(topenDb - tparseq)
          add ','
          add "\"query matching & conversion\":"
          add $inMicroseconds(tquery - topenDb)
          add ','
          add "\"exec & collect\":"
          add $inMicroseconds(tcollect - tquery)
          add '}'
          add '}'

        close db
        req.respond 200, jsonHeader(), acc
        debugEcho inMicroseconds(tcollect - thead), "us"

      except:
        let e = getCurrentExceptionMsg()
        req.respond 400, jsonHeader(), jsonError e
        debugEcho "did error ", e
        debugEcho jsonError e


    proc getEntity(req: Request, ent: Entity) =
      let
        thead = getMonoTime()
        id    = parseInt     req.queryParams["id"]
        db    = openSqliteDB app.config.storage.appDbFile
        q     = prepareGetQuery ent
        row   = db.getRow(q, id)
        tdone = getMonoTime()
      logSql q
      close db
      req.respond 200, jsonHeader(), row[0]
      debugEcho inMicroseconds(tdone - thead), "us"

    proc getNode(req: Request) =
      getEntity req, nodes

    proc getEdge(req: Request) =
      getEntity req, edges


    proc insertNodes(req: Request) =
      let
        thead  = getMonoTime()
        j      = parseJson req.body
        db     = openSqliteDB app.config.storage.appDbFile
        q      = prepareNodeInsertQuery()
      
      logSql q
      var ids: seq[int]
      for a in j:
        let
          tag    = parseTag getstr a["tag"]
          doc    =                $a["doc"]
          id     = db.insertID(q, tag, doc)
        ids.add id

      close db
      let tdone  = getMonoTime()

      debugEcho inMicroseconds(tdone - thead), "us"
      req.respond 200, jsonHeader(), jsonIds ids

    proc insertEdges(req: Request) =
      let
        thead  = getMonoTime()
        j      = parseJson req.body
        db     = openSqliteDB app.config.storage.appDbFile
        q      = prepareEdgeInsertQuery()
      
      logSql q
      var ids: seq[int]
      for a in j:
        let
          tag    = parseTag getstr a["tag"]
          source =          getInt a["source"]
          target =          getInt a["target"]
          doc    =                $a["doc"]
          id     = db.insertID(q, tag, source, target, doc)
        
        ids.add id

      close db
      let tdone  = getMonoTime()

      debugEcho inMicroseconds(tdone - thead), "us"
      req.respond 200, jsonHeader(), jsonIds ids


    proc updateEntity(req: Request, ent: Entity) =
      let
        j   = parseJson req.body
        q   = prepareUpdateQuery ent

      logSql q

      if j.kind == JObject:
        let db  = openSqliteDB    app.config.storage.appDbFile
        
        var acc: seq[int]
        for k, v in j:
          let 
            id       = parseint k
            doc      = $v
            affected = db.execAffectedRows(q, doc, id)

          if affected == 1:
            acc.add id

        close db
        req.respond 200, jsonHeader(), jsonAffectedRows(acc.len, acc)
        
      else:
        raisee "invalid json object for update. it should be object of {id => new_doc}"

    proc updateNodes(req: Request) =
      updateEntity req, nodes

    proc updateEdges(req: Request) =
      updateEntity req, edges


    proc deleteEntity(req: Request, ent: Entity) =
      let
        j        = parseJson req.body
        ids      = j["ids"].to seq[int]
        db       = openSqliteDB    app.config.storage.appDbFile
        q        = prepareDeleteQuery(ent, ids)
        affected = db.execAffectedRows q
      logSql q
      close db
      req.respond 200, jsonHeader(), jsonAffectedRows affected

    proc deleteNodes(req: Request) =
      deleteEntity req, nodes

    proc deleteEdges(req: Request) =
      deleteEntity req, edges

  proc initRouter: Router = 
    with result:
      get    "/",                       indexPage
      get    "/static/",                staticFiles

      # get    "/api/login/",             apiDatabasesOfUser
      # get    "/api/signup/",            apiDatabasesOfUser

      # get    "/api/users/",             apiDatabasesOfUser
      # get    "/api/user/",              apiDatabasesOfUser

      # get    "/api/databases/",         apiDatabasesOfUser
      # post   "/api/database/",          apiDatabasesOfUser

      # get    "/api/database/blueprint/",  gqlService
      # post   "/api/database/blueprint/",  gqlService

      # get    "/api/database/stats/",    gqlService

      post   "/api/database/query/",    askQuery


      get    "/api/database/node/",     getNode
      get    "/api/database/edge/",     getEdge

      post   "/api/database/nodes/",    insertNodes
      post   "/api/database/edges/",    insertEdges

      put    "/api/database/nodes/",    updateNodes
      put    "/api/database/nodes/",    updateEdges

      delete "/api/database/nodes/",    deleteNodes
      delete "/api/database/edges/",    deleteEdges

      # get    "/api/database/indexes/",  gqlService
      # post   "/api/database/index/",    gqlService
      # delete "/api/database/index/",    gqlService


  app = App(
    server:                 newServer initRouter(),
    config:                 config,
    defaultQueryStrategies: parseQueryStrategies ctx.tomlConf,
  )
  app

proc run(app: App) {.noreturn.} = 
  echo fmt"running in {app.config.url}"
  serve app.server, app.config.server.port, app.config.server.host


when isMainModule:
  let
    ctx  = loadAppContext "./config.toml"
    conf = buildConfig    ctx
    app  = initApp(ctx, conf)

  run app
