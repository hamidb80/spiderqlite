# Package

version       = "0.0.3"
author        = "hamidb80"
description   = """
  SpiderQL is query abstraction library & managed database server
  which aims to model graph structure in SQL.
"""
license       = "MIT"
srcDir        = "src"
bin           = @["server"]


# Dependencies

requires "nim >= 2.0.0"

requires "db_connector"   # https://github.com/nim-lang/db_connector

requires "webby"          # https://github.com/treeform/webby
requires "mummy"          # https://github.com/guzba/mummy
requires "waterpark"      # https://github.com/guzba/waterpark
requires "parsetoml"      # https://github.com/NimParsers/parsetoml
requires "questionable"   # https://github.com/codex-storage/questionable
requires "cookiejar"      # https://github.com/planety/cookiejar

requires "pretty"         # https://github.com/treeform/pretty


task dev, "development run": 
  exec "nim --deepcopy:on -d:useMalloc -d:debug   r src/server.nim ./docs/dev.toml --dump-config"

task rel, "release run": 
  exec "nim --deepcopy:on -d:useMalloc -d:release r src/server.nim ./docs/release.toml"
