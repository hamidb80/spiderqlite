import std/[os, options, paths, strutils, strformat, tables, nativesockets]

import parsetoml, mummy

import ../utils/other



type
  AdminConfig* = object
    enabled* : bool
    username*: string
    password*: Password

  UsersConfig* = object
    maxDatabases*: Natural
    verificationAfterSignup*: bool

  # TODO each database has some queries to explore
  # PlaygroundConfig* = object

  # TODO in database page get random node and edge of each tag and show its strcuture [fields with types] 
    

  ServerConfig* = object
    host*: Host
    port*: Port

  StorageConfig* = object
    appDbFile*:  Path
    usersDbDir*: Path
    backupDir*:  Path

  FrontendConfig* = object
    enabled*: bool

  LogConfig* = object
    config*:      bool
    sql*:         bool
    reqbody*:     bool
    performance*: bool

  AppConfig* = ref object
    admin*:    AdminConfig
    users*:    UsersConfig

    server*:   ServerConfig
    frontend*: FrontendConfig

    storage*:  StorageConfig

    logs*:     LogConfig

    open_browser*: bool
    queryStrategyFile*: Path


  ParamTable*  = Table[string, string]

  AppContext* = ref object
    cmdParams*: ParamTable
    tomlConf*:  TomlValueRef


func `$`*(p: Port): string = 
  $p.int

func `$`*(p: Path): string = 
  p.string


func conv(val: string, typ: type string): string = 
  val

func conv(val: string, typ: type int): int = 
  parseInt val
  
func conv(val: string, typ: type Port): Port = 
  Port val.conv int

func conv(val: string, typ: type Path): Path = 
  # FIXME check is a valid path
  Path val

func conv(val: string, typ: type Host): Host = 
  # FIXME check is a valid Host
  Host val

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

proc v[T](ctx: AppContext, cmd, env, path: string, convType: typedesc[T]): T = 
  let maybeValue = 
    getParam(ctx.cmdParams, cmd)  or
    getOsEnv(env)                 or
    getNested(ctx.tomlConf, path) 

  if issome maybeValue:
    conv get maybeValue, convType
  else:
    raisee "none of these config keys found : " & $(cmd, env, path)



proc buildConfig*(ctx: AppContext): AppConfig = 
  ## TODO add maximum concurrent read connection for a database
  #  sTOdo playDbFile: v(ctx, "--play-db-file", "SPQL_PLAY_DB_FILE", "storage.play_db_file", Path),
  
  AppConfig(
    server: ServerConfig(
      host:  v(ctx, "--host", "SPQL_HOST", "server.host", Host),
      port:  v(ctx, "--port", "SPQL_PORT", "server.port", Port),
    ),
    frontend: FrontendConfig(
      enabled:  v(ctx, "--frontend-enabled", "SPQL_FRONTEND_ENABLED", "frontend.enabled", bool),
    ),
    admin: AdminConfig(
      enabled:  v(ctx, "--admin-enabled",  "SPQL_ADMIN_ENABLED",  "admin.enabled",  bool),
      username: v(ctx, "--admin-username", "SPQL_ADMIN_USERNAME", "admin.username", string),
      password: v(ctx, "--admin-password", "SPQL_ADMIN_PASSWORD", "admin.password", Password),
    ),
    users: UsersConfig(
      maxDatabases:            v(ctx, "--user-max-dbs",            "SPQL_USER_MAX_DBS",            "users.max_dbs",            Natural),
      verificationAfterSignup: v(ctx, "--user-needs-verification", "SPQL_USER_NEEDS_VERIFICATION", "users.needs_verification", bool),
    ),
    storage: StorageConfig(
      appDbFile:  v(ctx, "--app-db-file",  "SPQL_APP_DB_FILE",  "storage.app_db_file",  Path),
      usersDbDir: v(ctx, "--users-db-dir", "SPQL_USERS_DB_DIR", "storage.users_db_dir", Path),
      backupDir:  v(ctx, "--backup-dir",   "SPQL_BACKUP_DIR",   "storage.backup_dir",   Path),
    ),

    logs: LogConfig(
      config:      v(ctx, "--dump-config",       "SPQL_DUMP_CONFIG",       "logs.config",      bool),
      sql:         v(ctx, "--log-generated-sql", "SPQL_LOG_GENERATED_SQL", "logs.sql",         bool),
      reqbody:     v(ctx, "--log-request-body",  "SPQL_LOG_REQUEST_BODY",  "logs.req_body",    bool),
      performance: v(ctx, "--log-performance",   "SPQL_LOG_PERFORMANCE",   "logs.performance", bool),
    ),

    open_browser:      v(ctx, "--open-browser", "SPQL_OPEN-BROWSER", "open_browser", bool),
    queryStrategyFile: v(ctx, "--query-strategy-file-path", "SPQL_QS_FPATH", "query_strategy_file_path", Path),
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
  fmt"http://{conf.server.host}:{conf.server.port}"
