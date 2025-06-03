## routes will be defined here to cross access
## 
import std/[strutils, uri, macros, sequtils, strformat]
import macroplus


func nimFriendly(name: string): string = 
    replace name, '-', '_'

func toUrlVarName(name: string): string = 
    name.nimFriendly & "_raw_url"

func toUrlProcName(name: string): string = 
    name.nimFriendly & "_url"

func safeUrl*(i: SomeNumber or bool): string {.inline.} =
  $i

func safeUrl*(s: string): string {.inline.} =
  encodeUrl s

proc dispatchInfo(entry: NimNode): tuple[url: NimNode, args: seq[NimNode]] =
  expectKind  entry, nnkInfix
  expectIdent entry[0], "?"
  (entry[1], entry[2][0..^1])

func toIdentDef(e: NimNode): NimNode =
  expectKind e, nnkExprColonExpr
  newIdentDefs(e[0], e[1])


macro br*(nnode): untyped = 
  ## ident of correspoding function which computes url
  ident toUrlVarName  strval nnode

macro b*(nnode): untyped = 
  ## ident of correspoding var which stores raw url
  ident toUrlProcName strval nnode

macro defRoute*(nameLit, path): untyped =
  result = newStmtList()

  let
    name           = strval              namelit
    dinfo          = dispatchInfo        path
    url            = strVal              dinfo.url
    procname       = ident toUrlProcName name
    urlVarName     = ident toUrlVarName  name
    procbody       = block:
      if dinfo.args.len == 0: newlit url
      else:
        var patt = url & "?"

        for i, r in dinfo.args:
          if i != 0:
            add patt, '&'
          let n = r[IdentDefName].strVal
          add patt, join [n, "={safeUrl ", n, "}"]

        newTree(nnkCommand, ident"fmt", newLit patt)

  add result, newConstStmt(exported urlVarName, newlit url)
  add result, newproc(
        exported(procname),
        @[ident"string"] & dinfo.args.map(toIdentDef),
        procbody)


# -------------------------------------------------------


defRoute "static-files",     "/static/**"     ?  ()

defRoute "landing",          "/"              ?  ()
defRoute "docs",             "/docs/"         ?  ()
defRoute "playground",       "/playground/"   ?  ()

defRoute "sign-up",          "/sign-up/"      ?  ()
defRoute "sign-in",          "/sign-in/"      ?  ()
defRoute "sign-in-api",      "/api/sign-in/"  ?  ()
defRoute "sign-out",         "/sign-out/"     ?  ()
defRoute "profile",          "/profile/"      ?  (u: string)
defRoute "users-list",       "/users/"        ?  ()

defRoute "database",          "/database/"           ?  (u: string, db: string)
defRoute "database-download", "/database/download/"  ?  (u: string, db: string)

defRoute "api-home",             "/api/"                 ? ()
defRoute "api-query-database",   "/api/database/query/"  ? ()
defRoute "api-get-node-by-id",   "/api/database/node/"   ? ()
defRoute "api-get-edge-by-id",   "/api/database/edge/"   ? ()
defRoute "api-insert-nodes",     "/api/database/nodes/"  ? ()
defRoute "api-insert-edges",     "/api/database/edges/"  ? ()
defRoute "api-update-nodes",     "/api/database/nodes/"  ? ()
defRoute "api-update-edges",     "/api/database/nodes/"  ? ()
defRoute "api-delete-nodes",     "/api/database/nodes/"  ? ()
defRoute "api-delete-edges",     "/api/database/edges/"  ? ()
