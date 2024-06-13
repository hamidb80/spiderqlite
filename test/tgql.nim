import std/[json, sugar]

import db_connector/db_sqlite

import gql
import utils/other


proc echoRows(db: DbConn, sql: SqlQuery, fout: File = stdout) = 
  for row in db.getAllRows sql:
    for cell in row:
      fout.write:
        try:
          cell.parseJson.pretty 4
        except:
          cell
      fout.write ", "
    fout.write "\n"

when isMainModule:
  let
    queryStrategies = parseQueryStrategies parseToml readfile "./examples/qs.toml"
    ctx             = %*{"mtitle": "ZORRO ARK"}

  for path in [
    # "./test/sakila/get.gql",
    "./test/sakila/get_agg.gql",
    # "./test/sakila/simple1.gql",
    # "./test/sakila/5cond.gql",
    # "./test/sakila/get_ignore.gql",
  ]:
    let
      parsedGql = parseGql readFile   path
      graphDB   = openSqliteDB        "./temp/graph.db"
      sql       = toSql(
        parsedGql, 
        queryStrategies, 
        s => $ctx[s])

    echo   sql
    # print  parsedGql
    echoRows graphDB, sql
