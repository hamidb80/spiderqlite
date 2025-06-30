import std/[strutils, strformat, os, tables]

import mummy, mummy/routers

import ../query_language/[core]
import ../utils/other
import routes
import ./[model, config, controllers]

# APP INIT -------------------------------------

proc initApp(config: AppConfig): App = 
  preapreStorage config

  var app = App(config: config)

  proc initRouter: Router = 
    
    template rr(fn): untyped = 
      proc (req: Request): void = 
        fn(req, app)

    if config.frontend.enabled:
      get    result,    br"landing",               rr pageLanding
      get    result,    br"static-files",          rr filesStaticServ
      get    result,    br"docs",                  rr pageDocs
      get    result,    br"playground",            rr pageDatabaseList

      get    result,    br"database",              rr pageDatabase 
      post   result,    br"database",              rr pageDatabase 
      get    result,    br"database-download",     rr filesDatabaseDownload

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

# TODO add more examples
# TODO add presentation
# TODO make it work via FFI
echo "\n\nTODO show errors to user in query page\n\n"

#[

  #movie m
  #acted_in a
  #person p
    = 
      .name
      "KARL BERRY"

  ask ^p>-a->m
  draw  a

  ------------------------------

  #movie m1
  #movie m2
  #acted_in a1
  #acted_in a2
  #person p
    = 
      .name
      "KARL BERRY"

  ask m2<-a2-<p>-a1->m1
  draw  a1 a2

]#

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
