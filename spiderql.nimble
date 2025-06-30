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
requires "parsetoml"      # https://github.com/NimParsers/parsetoml
requires "questionable"   # https://github.com/codex-storage/questionable

task dev, "development run":
  # https://github.com/nim-lang/choosenim/issues/27
  exec "nim --deepcopy:on -d:useMalloc -d:debug --mm:arc -d:ssl r src/backend/server.nim ./docs/dev.toml --dump-config"
