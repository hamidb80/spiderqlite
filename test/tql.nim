import std/[json, sugar, strutils]

import db_connector/db_sqlite
import parsetoml

import query_language/[core, parser]
import utils/other
import pretty


func extractStrategies*(tv: TomlValueRef): seq[TomlValueRef] = 
  getElems tv["strategies"]


when isMainModule:
  const sample =   
    # """
    #   #user u
    #   ask   u
    #   ret
    #     + 
    #       1  
    #       u.__id
    # """
    
    # """
    # #user u
    # ask   u
    # ret   
    #   + 1 u.__id
    # """

    """
    #user u
    ask   u
    ret   
      graph! u
    """


    # BUG `ret + 1 1` does not work, you should make a new line

  let
    qs   = parseQueryStrategies extractStrategies parseTomlFile "./docs/strategies.toml"
    ctx  = %*{"mtitle": "ZORRO ARK"}
    pq   = parseSpql sample
    sql  = toSql(pq, qs, _ => "")

  print pq
  echo strip string sql
