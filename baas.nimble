# Package

version       = "0.0.1"
author        = "hamidb80"
description   = "Backend as a Service"
license       = "MIT"
srcDir        = "src"
bin           = @["baas"]


# Dependencies

requires "nim >= 2.0.0"

requires "db_connector"   # https://github.com/nim-lang/db_connector
requires "iterrr"         # https://github.com/hamidb80/iterrr
requires "questionable"   # https://github.com/codex-storage/questionable
requires "yanyl"          # https://github.com/tanelso2/yanyl
requires "pretty"         # https://github.com/treeform/pretty