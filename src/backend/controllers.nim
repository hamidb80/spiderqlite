import std/[strformat, paths, mimetypes, json, tables, uri, sugar, strutils, os, times, monotimes, math, sequtils, options]


import ../query_language/[parser, core]
import ../utils/other
import ../bridge
import ./[config, view]


import db_connector/db_sqlite
import mummy, mummy/routers
import webby
import parsetoml

# TODO use waterpark
# import pretty

using 
  req: Request
  app: App

# Helpers -------------------------------------------

func dbPath(app; dbname: string): string = 
  app.config.storage.dbDir.string / dbname & ".db"

func jsonHeader: HttpHeaders = 
  toWebby @{"Content-Type": "application/json"}

func htmlHeader: HttpHeaders = 
  toWebby @{"Content-Type": "text/html"}

proc getMimetype(ext: string): string = 
  # XXX move out for performance
  var m = newMimetypes()
  m.getMimetype ext

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

  for edgeGroup in queryResult:
    for arr in edgeGroup:
    # for arr in queryResult:
      add result.nodeIds, arr[1].getint
      add result.nodeIds, arr[2].getint
      add result.edgeIds, arr[0].getint  

template logBody: untyped {.used.} =
  if app.config.logs.reqbody:
    echo req.body

template logSql(q): untyped {.used.} =
  if app.config.logs.sql:
    echo q

template withDb(dbname, body): untyped =
  # TODO error handling
  let db {.inject.} = openSqliteDB app.config.storage.dbdir.string /  dbname & ".db"
  body
  close db
  
template logPerf(body): untyped {.used.} =
  let thead = getMonoTime()
  body
  let ttail = getMonoTime()
  if app.config.logs.performance:
    let tdelta = ttail - thead
    echo inMicroseconds tdelta, "us"

# Controllers -------------------------------------------

proc apiAskQuery*(req; app;) =
  try:
    let j = parseJson req.body
    withdb req.queryParams["db"]:
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
  withDB req.queryParams["db"]:
    let val   = getEntityDbRaw(db, id, ent)
    
  # XXX logSql
  req.respond 200, jsonHeader(), val

proc apiGetNode*(req: Request, app: App) = 
  getEntity req, app, nodes

proc apiGetEdge*(req: Request, app: App) = 
  getEntity req, app, edges

proc apiInsertNodes*(req; app;) = 
  let j = parseJson req.body
  withDB req.queryParams["db"]:
    let ids = collect:
      for n in j:
        insertNodeDB db, parseTag getstr n["tag"], n["doc"]

  req.respond 200, jsonHeader(), jsonAffectedRows(len ids, ids)

proc apiInsertEdges*(req; app;) = 
  let j = parseJson req.body
  withDB req.queryParams["db"]:
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
    withDB req.queryParams["db"]:
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
  withDB req.queryParams["db"]:
    let affected = deleteEntitiesDB(db, ent, ids)
  req.respond 200, jsonHeader(), jsonAffectedRows affected

proc apiDeleteNodes*(req; app;) = 
  deleteEntity req, app, nodes

proc apiDeleteEdges*(req; app;) = 
  deleteEntity req, app, edges

proc apiHome*(req; app;) =
  req.respond 200, jsonHeader(), $ %*{
    "status": "ok",
  }

# ------------------------

proc filesStaticServ*(req; app) =
  let
    fname   = "./assets/" & req.uri.splitPath.tail
    ext     = fname.splitFile.ext.strip(chars= {'.'}, trailing = false)
    content = readfile fname

  req.respond 200, toWebby @{"Content-Type": getMimetype ext} , content

proc pageLanding*(req; app) =
  req.respond 200, htmlHeader(), landingPageHtml()

proc pageDocs*(req; app) = 
  req.respond 200, htmlHeader(), docsPageHtml()

proc pageDatabaseList*(req; app) = 
  let pre  = app.config.storage.dbDir.string
  let fnames = collect:
    for fpath in walkFiles pre / "*.db":
      (fpath.splitFile.name, getFileSize fpath)

  req.respond 200, htmlHeader(), databaseListPageHtml fnames

proc pageDatabase*(req; app) = 
  let 
    dbname = req.queryParams["db"] 
    path   = app.dbPath dbname

  withDb dbname:
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

          queryResponse = db.askQueryDB(
            %*{},
            spql, 
            app.defaultQueryStrategies)

        queryReuslts = queryResponse["result"]
        debugecho queryReuslts

        perf  = (getMonoTime() - head).inMicroseconds

        if spql.getVerb.visualize:
          let (nodeids, edgeids) = extractVisEdges queryReuslts
          nodesGroup = db.getNodesDB(nodeids)
          edgesGroup = db.getEdgesDB(edgeids)

  req.respond 200, htmlHeader(), databasePageHtml(
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
  let dbname = req.queryParams["db"]

  req.respond(200, 
    toWebby @{
      "Content-Type": "application/octet-stream",
      "Content-Disposition": fmt "attachment; filename=\"{dbname}.db.sqlite3\"",
    }, 
    readfile app.dbPath(dbname))
