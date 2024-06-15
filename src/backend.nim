import std/[tables, strutils, strformat, json, monotimes, times, with, sugar]

import db_connector/db_sqlite
import mummy, mummy/routers
import parsetoml

import gql
import ./utils/other
import ./config


type
  App* = object
    server*: Server
    config*: AppConfig
    defaultQueryStrategies*: QueryStrategies
    systemSqlQueries*:       Table[string, seq[SqlPatSep]]


func joinComma(s: sink seq): string = 
  s.join ","  

func sqlize(s: seq[int]): string = 
  '(' & s.joinComma & ')'

func jsonAffectedRows(n: int, ids: seq[int] = @[]): string = 
  "{\"affected_rows\":" & $n & ", \"ids\": [" & ids.joinComma & "]}"

func jsonId(id: int): string = 
  "{\"id\":" & $id & "}"


func parseSystemQueries*(tv: TomlValueRef): Table[string, seq[SqlPatSep]] =
  for k, v in tv["system"].tableVal:
    result[k] = preProcessRawSql getstr v["sql"]

func resolve(s: seq[SqlPatSep], lookup: openArray[string]): string =
  for i, p in s:
    let x = i div 2
    add result:
      case p.kind
      of sqkStr:     p.content
      of sqkCommand: lookup[x]

proc initApp(ctx: AppContext, config: AppConfig): App = 
  var app: App

  unwrap controllers:
    proc indexPage(req: Request) =
      req.respond 200, emptyHttpHeaders(), "hey! use APIs for now!"

    proc staticFiles(req: Request) =
      discard

    proc askQuery(req: Request) {.gcsafe.} =
      let 
        thead           = getMonoTime()
        j               = parseJson req.body
        ctx             = j["context"]
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

      debugEcho sql
      var rows = 0
      var acc = newStringOfCap 1024 * 100 # 100 KB
      acc.add "{\"result\": ["
      
      for row in db.fastRows sql:
        inc rows
        acc.add row[0]
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
      req.respond 200, emptyHttpHeaders(), acc

    proc getEntity(req: Request, def, ret: string) =
      let
        thead           = getMonoTime()
        id    = parseInt     req.queryParams["id"]
        db    = openSqliteDB app.config.storage.appDbFile
        query = resolve(app.systemSqlQueries[def], [ret, $id])
        row   = db.getRow sql query
        tdone           = getMonoTime()

      close db
      req.respond 200, emptyHttpHeaders(), row[0]
      debugEcho inMicroseconds(tdone - thead), "us"

    proc getNode(req: Request) =
      getEntity req, "get_node", sqlJsonNodeExpr "" 

    proc getEdge(req: Request) =
      getEntity req, "get_edge", sqlJsonEdgeExpr ""

    # TODO add minimal option if enables only returns "id"
    proc insertNode(req: Request) =
      let
        thead           = getMonoTime()
        j      = parseJson req.body
        tag    = parseTag getstr j["tag"]
        doc    =                $j["doc"]
        query  = resolve(app.systemSqlQueries["insert_node"], [
          dbQuote tag, 
          dbQuote doc
        ])
        db     = openSqliteDB app.config.storage.appDbFile
        id     = db.insertID sql query
        tdone           = getMonoTime()

      close db
      debugEcho inMicroseconds(tdone - thead), "us"
      req.respond 200, emptyHttpHeaders(), jsonId id

    proc insertEdge(req: Request) =
      let
        thead           = getMonoTime()
        j      = parseJson req.body
        tag    = parseTag getstr j["tag"]
        source =          getInt j["source"]
        target =          getInt j["target"]
        doc    =                $j["doc"]
        query  = resolve(app.systemSqlQueries["insert_edge"], [
          dbQuote tag, 
          $source,
          $target,
          dbQuote doc,
        ])
        db     = openSqliteDB app.config.storage.appDbFile
        id     = db.insertID sql query
        tdone           = getMonoTime()

      close db
      debugEcho inMicroseconds(tdone - thead), "us"
      req.respond 200, emptyHttpHeaders(), jsonId id


    proc updateEntity(req: Request, ent: string) =
      let
        j   = parseJson req.body
        db  = openSqliteDB    app.config.storage.appDbFile

      assert j.kind == JObject
      var acc: seq[int]
      for k, v in j:
        let 
          id       = parseint k
          doc      = $v
          query    = resolve(app.systemSqlQueries[ent], [
            dbQuote $doc,
            $id])
          affected = db.execAffectedRows sql query

        debugEcho query
        if affected == 1:
          acc.add id

      close db
      req.respond 200, emptyHttpHeaders(), jsonAffectedRows(acc.len, acc)

    proc updateNodes(req: Request) =
      updateEntity req, "update_nodes"

    proc updateEdges(req: Request) =
      updateEntity req, "update_edges"


    proc deleteEntity(req: Request, ent: string) =
      let
        j        = parseJson req.body
        ids      = j["ids"].to seq[int]
        db       = openSqliteDB    app.config.storage.appDbFile
        affected = db.execAffectedRows sql resolve(app.systemSqlQueries[ent], [
          sqlize ids
        ])
      close db
      req.respond 200, emptyHttpHeaders(), jsonAffectedRows affected

    proc deleteNodes(req: Request) =
      deleteEntity req, "delete_nodes"

    proc deleteEdges(req: Request) =
      deleteEntity req, "delete_edges"

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

      # get    "/api/database/stats/",    gqlService

      post   "/api/database/query/",    askQuery


      get    "/api/database/node/",     getNode
      get    "/api/database/edge/",     getEdge

      post   "/api/database/node/",     insertNode
      post   "/api/database/edge/",     insertEdge

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
    systemSqlQueries:       parseSystemQueries   ctx.tomlConf
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
