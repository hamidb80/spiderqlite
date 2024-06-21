# Package

version       = "0.0.2"
author        = "hamidb80"
description   = """
  SpiderQL is a query abstraction library and managed SQLite database server
"""
license       = "MIT"
srcDir        = "src"
bin           = @["spql_server"]


# Dependencies

requires "nim >= 2.0.0"

requires "db_connector"   # https://github.com/nim-lang/db_connector
requires "questionable"   # https://github.com/codex-storage/questionable
requires "parsetoml"      # https://github.com/NimParsers/parsetoml
requires "pretty"         # https://github.com/treeform/pretty
requires "webby"          # https://github.com/treeform/webby


task dev, "development run": 
  exec "nim --deepcopy:on -d:useMalloc -d:debug r src/server.nim ./docs/config.toml"
