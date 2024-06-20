import std/[strutils, strformat, tables, json, monotimes, os, times, with, sugar]

import db_connector/db_sqlite
import mummy, mummy/routers
import webby
import parsetoml

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


func extractStrategies(tv: TomlValueRef): seq[TomlValueRef] = 
  getElems tv["strategies"]

proc initApp(config: AppConfig): App = 
  var app = App(config: config)

  template logSql(q): untyped =
    if app.config.logs.sql:
      echo q

  template withDb(dbpath, body): untyped =
    let db {.inject.} = openSqliteDB dbPath
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
    proc indexPage(req: Request) =
      req.respond 200, jsonHeader(), "hey! use APIs for now!"

    # proc staticFiles(req: Request) =
    #   discard
      
    proc askQuery(req: Request) {.gcsafe.} =
      try:
        let 
          thead           = getMonoTime()
          j               = parseJson req.body
          ctx             = j["context"]

        echo j.pretty
        echo getstr j["query"]

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

        var 
          rows = 0
          acc = newStringOfCap 1024 * 100 # 100 KB

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
        echo inMicroseconds(tcollect - thead), "us"

      except:
        let e = getCurrentExceptionMsg()
        req.respond 400, jsonHeader(), jsonError e
        echo "did error ", e
        echo jsonError e


    proc getEntity(req: Request, ent: Entity) =
      logPerf:
        let
          id    = parseInt        req.queryParams["id"]
          q     = prepareGetQuery ent

        withDB app.config.storage.appDbFile:
          let row = getRow(db, q, id)
        
        logSql q
        req.respond 200, jsonHeader(), row[0]

    proc getNode(req: Request) =
      getEntity req, nodes

    proc getEdge(req: Request) =
      getEntity req, edges


    proc insertNodes(req: Request) =
      logPerf:
        let
          j      = parseJson req.body
          q      = prepareNodeInsertQuery()

        logSql q
        withDB app.config.storage.appDbFile:
          var ids: seq[int]
          for a in j:
            let
              tag    = parseTag getstr a["tag"]
              doc    =                $a["doc"]
              id     = db.insertID(q, tag, doc)
            ids.add id

        req.respond 200, jsonHeader(), jsonIds ids

    proc insertEdges(req: Request) =
      logPerf:
        let
          j      = parseJson req.body
          q      = prepareEdgeInsertQuery()
        
        logSql q
        withDB app.config.storage.appDbFile:
          var ids: seq[int]
          for a in j:
            let
              tag    = parseTag getstr a["tag"]
              source =          getInt a["source"]
              target =          getInt a["target"]
              doc    =                $a["doc"]
              id     = db.insertID(q, tag, source, target, doc)
            
            ids.add id

        req.respond 200, jsonHeader(), jsonIds ids


    proc updateEntity(req: Request, ent: Entity) =
      logPerf:
        let
          j   = parseJson req.body
          q   = prepareUpdateQuery ent

        logSql q

        if j.kind == JObject:

          withDB app.config.storage.appDbFile:

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

    proc updateNodes(req: Request) =
      updateEntity req, nodes

    proc updateEdges(req: Request) =
      updateEntity req, edges


    proc deleteEntity(req: Request, ent: Entity) =
      logPerf:
        let
          j        = parseJson req.body
          ids      = j["ids"].to seq[int]
          q        = prepareDeleteQuery(ent, ids)

        logSql q
        withDB app.config.storage.appDbFile:
          let affected = db.execAffectedRows q
        req.respond 200, jsonHeader(), jsonAffectedRows affected

    proc deleteNodes(req: Request) =
      deleteEntity req, nodes

    proc deleteEdges(req: Request) =
      deleteEntity req, edges

  proc initRouter: Router = 
    with result:
      get    "/",                       indexPage
      # get    "/static/",                staticFiles

      # get    "/api/login/",             apiDatabasesOfUser
      # get    "/api/signup/",            apiDatabasesOfUser

      # get    "/api/users/",             apiDatabasesOfUser
      # get    "/api/user/",              apiDatabasesOfUser

      # get    "/api/database/backups/",  backup
      # post   "/api/database/init/",     initDB
      # get    "/api/databases/",         apiDatabasesOfUser
      # post   "/api/database/",          apiDatabasesOfUser
      # delete "/api/database/",          delete database

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


  app.server                 = newServer initRouter()
  app.defaultQueryStrategies = parseQueryStrategies extractStrategies parseTomlFile config.queryStrategyFile
  app

proc run(app: App) = 
  echo fmt"running in {app.config.url}"
  serve app.server, app.config.server.port, app.config.server.host


when isMainModule:
  let
    cmdParams = toParamTable commandLineParams()
    confPath  = cmdParams.getOrDefault("", "./config.toml")

  echo "config file path: ", confPath

  let
    ctx = AppContext(
      cmdParams: cmdParams,
      tomlConf:  parseTomlFile confPath
    )
    conf = buildConfig ctx
    app  = initApp     conf

  run app
