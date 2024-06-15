import std/[os, options, paths, strutils]

import ./utils/other

import parsetoml, mummy


type
  AdminConfig* = object
    enabled*            : bool
    username*, password*: string

  ServerConfig* = object
    host*: string
    port*: Port

  StorageConfig* = object
    appDbFile*:  Path
    usersDbDir*: Path

  FrontendConfig* = object
    enabled*: bool

  AppConfig* = ref object
    admin*:    AdminConfig

    server*:   ServerConfig
    frontend*: FrontendConfig

    storage*:  StorageConfig

    # TODO load from numble file at compile file
    # version:

  AppContext* = ref object
    cmdParams*: seq[string]
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
      appDbFile:  v(ctx, "--app-db-file",  "SPIDERSQL_APP_DB_FILE",  "storage.app_db_file", "./temp/graph.db", Path),
      usersDbDir: v(ctx, "--users-db-dir", "SPIDERSQL_USERS_DB_DIR", "admin.users_db_dir",  "./temp/users/", Path),
    )
  )

proc loadAppContext*(configFilePath: string): AppContext = 
  AppContext(
    cmdParams: commandLineParams(),
    tomlConf:  parseToml.parseFile configFilePath)
