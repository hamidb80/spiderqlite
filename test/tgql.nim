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


when defined test_for_fns:
  echo firstLineIndentation """

    dasdks
      ds
    ads
    ad
  """
  echo firstLineIndentation """
  
    
    
  """

when isMainModule:

  const sample =   """
    #person   p
    #movie    m
      == m.id |mid|

    @acted_in a

    AS
      no_movies
      ()
        COUNT
        m.id

    -- *a means that include `p`s that may not have any edge `a` connected to `a` movie at all

    MATCH   ^p>-*a->m
    GROUP   p.id

    ORDER no_movies
    SORT  DESC 
    RETURN  
      {}
        "person"
        p

        "movies"
        [].
          m.title

        "no_movies"
        no_movies
  """

  let tokens = lexGql sample

  let ggg  = parseSpQl tokens

  print ggg
