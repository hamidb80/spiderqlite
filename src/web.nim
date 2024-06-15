import std/[json, strformat, with, os, strutils, sugar, monotimes, times, paths, options]

import db_connector/db_sqlite
import mummy, mummy/routers
import parsetoml

import gql
import ./utils/other


type
  AdminConfig = object
    enabled           : bool
    username, password: string

  ServerConfig = object
    host: string
    port: Port

  StorageConfig = object
    appDbFile:  Path
    usersDbDir: Path

  FrontendConfig = object
    enabled: bool

  AppConfig = ref object
    admin:    AdminConfig

    server:   ServerConfig
    frontend: FrontendConfig

    storage:  StorageConfig

    # TODO load from numble file at compile file
    # version:

  AppContext = ref object
    cmdParams: seq[string]
    tomlConf:  TomlValueRef
    
  App = object
    server: Server
    config: AppConfig

func conv(val: string, typ: type string): string = 
  val

func conv(val: string, typ: type int): int = 
  parseInt val
  
func conv(val: string, typ: type Port): Port = 
  Port val.conv int

func conv(val: string, typ: type Path): Path = 
  # FIXME check is a valid path
  Path val

func conv(val: string, typ: type bool): bool = 
  case val
  of "t", "true",  "True",  "TRUE", "yes", "Y": true
  of "f", "false", "False", "FALSE", "no", "N": false
  else: raisee "invalid bool value: " & val
  

func getParam(params: seq[string], key: string): Option[string] = 
  for i in countup(0, params.high, 2):
    if params[i] == key: 
      return some params[i+1]

func getNested(data: TomlValueRef, nestedKey: string): Option[string] =
  var curr = data["config"]

  for key in nestedKey.split '.':
    if curr.kind == TomlValueKind.Table and key in curr: 
      curr = curr[key]
    else:
      return
  
  ignore:
    some:
      case curr.kind
      of TomlValueKind.Float:  $getFloat curr
      of TomlValueKind.Int:    $getInt curr
      of TomlValueKind.String:  getStr curr
      of TomlValueKind.Bool:   $getBool curr
      else: raisee "invalid value" & $curr

proc getOsEnv(key: string): Option[string] =
  let t = getEnv key
  
  if isEmptyOrWhitespace t: none string
  else:                     some t

template `or`[T](a, b: Option[T]): Option[T] = 
  if isSome a: a
  else:        b

template `or`[T](a: Option[T], b: T): T = 
  if isSome a: get a
  else:            b


proc v[T](ctx: AppContext, cmd, env, path, def: string, convType: typedesc[T]): T = 
  let val = 
    getParam(ctx.cmdParams, cmd)  or
    getOsEnv(env)                 or
    getNested(ctx.tomlConf, path) or
    def

  conv val, convType

proc buildConfig(ctx: AppContext): AppConfig = 
  AppConfig(
    server: ServerConfig(
      host:  v(ctx, "--host", "SPIDERSQL_HOST", "server.host", "0.0.0.0", string),
      port:  v(ctx, "--port", "SPIDERSQL_PORT", "server.port", "6001",    Port),
    ),
    frontend: FrontendConfig(
      enabled:  v(ctx, "--frontend-enabled", "SPIDERSQL_FRONTEND_ENABLED", "frontend.enabled", "true", bool),
    ),
    admin: AdminConfig(
      enabled:  v(ctx, "--admin-enabled",  "SPIDERSQL_ADMIN_ENABLED",  "admin.enabled",  "false", bool),
      username: v(ctx, "--admin-username", "SPIDERSQL_ADMIN_USERNAME", "admin.username", "admin", string),
      password: v(ctx, "--admin-password", "SPIDERSQL_ADMIN_PASSWORD", "admin.password", "1234",  string),
    ),
    storage: StorageConfig(
      appDbFile:  v(ctx, "--app-db-file",  "SPIDERSQL_APP_DB_FILE",  "storage.app_db_file", "./temp/app.db", Path),
      usersDbDir: v(ctx, "--users-db-dir", "SPIDERSQL_USERS_DB_DIR", "admin.users_db_dir",  "./temp/users/", Path),
    )
  )

proc loadAppContext(configFilePath: string): AppContext = 
  AppContext(
    cmdParams: commandLineParams(),
    tomlConf:  parseToml.parseFile configFilePath)


func url(conf: AppConfig): string = 
  fmt"http://{conf.server.host}:{conf.server.port.int}/"


func parseTag(s: string): string = 
  if s.len == 0:    raisee "empty tag"
  elif s[0] == '#': s.substr 1
  else:             s

proc sqlize(s: seq[int]): string = 
  '(' & join(s, ",") & ')'

proc jsonAffectedRows(n: int, ids: seq[int] = @[]): string = 
  "{\"affected_rows\":" & $n & ", \"ids\": [" & ids.join(",") & "]}"


proc initApp(ctx: AppContext, config: AppConfig): App = 
  let defaultQueryStrategies = parseQueryStrategies ctx.tomlConf

  unwrap controllers:
    proc indexPage(req: Request) =
      req.respond(200, emptyHttpHeaders(), "hey! use APIs for now!")

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
        db              = openSqliteDB    "./temp/graph.db"
        topenDb         = getMonoTime()
        sql             = toSql(
          gql, 
          defaultQueryStrategies, 
          s => $ctx[s])
        tquery          = getMonoTime()

      # echo sql

      var acc = "{\"result\": ["
      
      for row in db.fastRows sql:
        acc.add row[0]
        acc.add ','

      if acc[^1] == ',': # check for 0 results
        acc.less
        
      acc.add ']'

      let tcollect = getMonoTime()

      with acc:
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


    proc getEntity(req: Request, entity, alias, select: string) =
      let
        id     = req.queryParams["id"]
        db     = openSqliteDB    "./temp/graph.db"
        row = db.getRow(sql fmt"""
          SELECT {select}
          FROM   {entity} {alias}
          WHERE  id = ?
        """, id)

      close db
      req.respond(200, emptyHttpHeaders(), row[0])

    proc getNode(req: Request) =
      getEntity req, "nodes", "n", sqlJsonNodeExpr "n"
      
    proc getEdge(req: Request) =
      getEntity req, "edges", "e", sqlJsonEdgeExpr "e"


    # TODO add minimal option if enables only returns "_id"
    proc createNode(req: Request) =
      let
        j      = parseJson req.body
        tag    = parseTag getstr j["tag"]
        doc    =                $j["doc"]
        db     = openSqliteDB    "./temp/graph.db"

      let id = db.insertID(sql """
        INSERT INTO
        nodes  (tag, doc) 
        VALUES (?,   ?)
      """, tag, doc)

      close db
      req.respond(200, emptyHttpHeaders(), "{\"_id\":" & $id & "}")

    proc createEdge(req: Request) =
      let
        j      = parseJson req.body
        tag    = parseTag getstr j["tag"]
        source =          getInt j["source"]
        target =          getInt j["target"]
        doc    =                $j["doc"]
        db     = openSqliteDB    "./temp/graph.db"

      let id = db.insertID(sql """
        INSERT INTO
        edges  (tag, source, target, doc) 
        VALUES (?,   ?,      ?,      ?)
      """, tag, source, target, doc)

      close db
      req.respond(200, emptyHttpHeaders(), "{\"_id\":" & $id & "}")


    proc updateEntity(req: Request, entity: string) =
      let
        j   = parseJson req.body
        db  = openSqliteDB    "./temp/graph.db"

      assert j.kind == JObject
      var acc: seq[int]
      for k, v in j:
        let 
          id       = parseint k
          doc      = $v
          affected = db.execAffectedRows(sql fmt"""
            UPDATE {entity}
            SET    doc = ?
            WHERE  id  = ?
          """, doc, id)

        if affected == 1:
          acc.add id

      close db
      req.respond(200, emptyHttpHeaders(), jsonAffectedRows(acc.len, acc))

    proc updateNodes(req: Request) =
      updateEntity req, "nodes"

    proc updateEdges(req: Request) =
      updateEntity req, "edges"


    proc deleteEntity(req: Request, entity: string) =
      let
        j        = parseJson req.body
        ids      = j["ids"].to seq[int]
        db       = openSqliteDB    "./temp/graph.db"
        affected = db.execAffectedRows(sql fmt"""
          DELETE FROM  {entity}
          WHERE  id IN {sqlize ids} 
        """)

      close db
      req.respond(200, emptyHttpHeaders(), jsonAffectedRows affected)

    proc deleteNodes(req: Request) =
      deleteEntity req, "nodes"

    proc deleteEdges(req: Request) =
      deleteEntity req, "edges"

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

      post   "/api/database/node/",     createNode
      post   "/api/database/node/",     createEdge

      put    "/api/database/nodes/",    updateNodes
      put    "/api/database/nodes/",    updateEdges

      delete "/api/database/nodes/",    deleteNodes
      delete "/api/database/edges/",    deleteEdges

      # get    "/api/database/indexes/",  gqlService
      # post   "/api/database/index/",    gqlService
      # delete "/api/database/index/",    gqlService

  App(
    server: newServer initRouter(),
    config: config
  )

proc run(app: App) = 
  echo "running in " & app.config.url
  serve app.server, app.config.server.port, app.config.server.host


when isMainModule:
  let
    ctx    = loadAppContext "./config.toml"
    config = buildConfig    ctx
    app    = initApp(ctx, config)

  run app
