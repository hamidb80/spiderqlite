import std/[json, sugar, strutils]

import db_connector/db_sqlite
import parsetoml

import query_language/[core, parser]
import utils/other
import pretty


func extractStrategies*(tv: TomlValueRef): seq[TomlValueRef] = 
  getElems tv["strategies"]


when isMainModule:
  const allEdges =   
    # """ 
    # #; x 
    # #; y 
    # #; w
    # ask x>-^y->w
    # ret 
    #   graph! y
    # """

    """ 
    #; x y w
    ask x>-^y->w
    ret 
      graph! y
    """


    # BUG `ret + 1 1` does not work, you should make a new line

  let
    qs   = parseQueryStrategies extractStrategies parseTomlFile "./docs/strategies.toml"
    ctx  = %*{"mtitle": "ZORRO ARK"}
    pq   = parseSpql allEdges
    sql  = toSql(pq, qs, _ => "")

  print pq
  echo strip string sql
