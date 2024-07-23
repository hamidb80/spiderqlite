## routes will be defined here to cross access
## 
import std/[strutils, uri, macros, sequtils]
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
  case entry.kind
  of nnkStrLit: (entry, @[])
  of nnkInfix:  (entry[1], entry[2][0..^1])
  else:         raise newException(ValueError, "?")

func toIdentDef(e: NimNode): NimNode =
  expectKind e, nnkExprColonExpr
  newIdentDefs(e[0], e[1])


macro defUrl*(nameLit, path): untyped =
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

  result.add newConstStmt(exported urlVarName, newlit url)
  result.add newproc(
        exported(procname),
        @[ident"string"] & dinfo.args.map(toIdentDef),
        procbody)


defUrl "sign-in",                "/sign-in/"    ? ()
defUrl "sign-up",                "/sign-up/"    ? ()
defUrl "sign-out",               "/sign-out/"   ? ()

defUrl "my-profile",             "/profile/me/" ? ()
defUrl "user-profile",           "/profile/"    ? (id: Id)
