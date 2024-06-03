# Package

version       = "0.0.1"
author        = "hamidb80"
description   = "Backend as a Service"
license       = "GPL-3.0-or-later"
srcDir        = "src"
bin           = @["baas"]


# Dependencies

requires "nim >= 2.0.0"

requires "db_connector"
requires "iterrr"
requires "questionable"

