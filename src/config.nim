import std/[os, options, paths, strutils, strformat, tables]

import ./utils/other

import parsetoml, mummy


type
  AdminConfig* = object
    enabled* : bool
    username*: string
    password*: Password

  ServerConfig* = object
    host*: string
    port*: Port

  StorageConfig* = object
    appDbFile*:  Path
    usersDbDir*: Path

  FrontendConfig* = object
    enabled*: bool

  LogConfig* = object
    sql*: bool
    reqbody*: bool
    performance*: bool

  AppConfig* = ref object
    # TODO load from numble file at compile file
    # version:

    admin*:    AdminConfig

    server*:   ServerConfig
    frontend*: FrontendConfig

    storage*:  StorageConfig

    logs*:     LogConfig

    queryStrategyFile*: Path

  ParamTable*  = Table[string, string]

  AppContext* = ref object
    cmdParams*: ParamTable
    tomlConf*:  TomlValueRef
    

func conv(val: string, typ: type string): string = 
  val

func conv(val: string, typ: type int): int = 
  parseInt val
  
func conv(val: string, typ: type Port): Port = 
  Port val.conv int

func conv(val: string, typ: type Path): Path = 
  # FIXME check is a valid path
  Path val

func conv(val: string, typ: type Password): Password = 
  Password val


func conv(val: string, typ: type bool): bool = 
  case val
  of "t", "T", "true",  "True",  "TRUE", "yes", "Y", "1": true
  of "f", "F", "false", "False", "FALSE", "no", "N", "0": false
  else: raisee "invalid bool value: " & val
  

func getParam(paramsTab: ParamTable, key: string): Option[string] = 
  if key in paramsTab:
    some paramsTab[key]
  else:
    none string

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
      else: raisee "invalid toml value type: " & $curr.kind

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

proc buildConfig*(ctx: AppContext): AppConfig = 
  AppConfig(
    server: ServerConfig(
      host:  v(ctx, "--host", "SPQL_HOST", "server.host", "0.0.0.0", string),
      port:  v(ctx, "--port", "SPQL_PORT", "server.port", "6001",    Port),
    ),
    frontend: FrontendConfig(
      enabled:  v(ctx, "--frontend-enabled", "SPQL_FRONTEND_ENABLED", "frontend.enabled", "true", bool),
    ),
    admin: AdminConfig(
      enabled:  v(ctx, "--admin-enabled",  "SPQL_ADMIN_ENABLED",  "admin.enabled",  "false", bool),
      username: v(ctx, "--admin-username", "SPQL_ADMIN_USERNAME", "admin.username", "admin", string),
      password: v(ctx, "--admin-password", "SPQL_ADMIN_PASSWORD", "admin.password", "1234",  Password),
    ),
    storage: StorageConfig(
      appDbFile:  v(ctx, "--app-db-file",  "SPQL_APP_DB_FILE",  "storage.app_db_file",  "[invalid]", Path),
      usersDbDir: v(ctx, "--users-db-dir", "SPQL_USERS_DB_DIR", "storage.users_db_dir", "[invalid]",   Path),
    ),

    logs: LogConfig(
      sql:         v(ctx, "--log-generated-sql",  "SPQL_LOG_GENERATED_SQL",  "logs.sql",         "false", bool),
      reqbody:     v(ctx, "--log-request-body",  "SPQL_LOG_REQUEST_BODY",    "logs.req_body",    "false", bool),
      performance: v(ctx, "--log-performance",    "SPQL_LOG_PERFORMANCE",    "logs.performance", "false", bool),
    ),

    queryStrategyFile: v(ctx, "--query-strategy-file-path", "SPQL_QS_FPATH", "query_strategy_file_path", "[invalid]", Path),
  )

proc toParamTable*(params: seq[string]): ParamTable = 
  var 
    lastWasKey = false
    key        = ""

  template setTrue: untyped =
    result[key] = "t"

  for i, p in params:
    if p.startsWith "--":
      if lastWasKey:
        setTrue()
      key = p
      lastWasKey = true
    else:
      result[key] = p
      lastWasKey = false
  
  if lastWasKey:
    setTrue()


func url*(conf: AppConfig): string = 
  fmt"http://{conf.server.host}:{conf.server.port.int}"
