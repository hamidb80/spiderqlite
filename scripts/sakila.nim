## converts sakila DB to graph form
## https://github.com/siara-cc/sakila_sqlite3/


import db_connector/db_sqlite
import std/[json, tables, strutils]


when isMainModule:
  type
    Node = enum
      nFilm
      nActor
  
  var 
    vritualId: Table[(Node, int), int]

  let 
    sakilaDB = open("sakila.db", "", "", "")
    graphDB  = open("graph.db", "", "", "")

    schemeQuery = readFile "./sql/schema.sql"

  for q in schemeQuery.split ";":
    if not isEmptyOrWhitespace q:
      graphDB.exec sql q

  echo "films"
  for x in sakilaDB.fastRows sql"SELECT * FROM film f":
    let 
      oldid = parseint x[0]
      data = %*{
        "title": x[1],
      }
      newid = graphDB.insertID(
        sql"INSERT INTO nodes (tag, doc) VALUES ('movie',?)", 
        $data)
    vritualId[(nfilm, oldid)] = newid
    
  echo "actors"
  for x in sakilaDB.fastRows sql"SELECT * FROM actor a":
    let
      oldid = parseint x[0]
      data = %*{
        "name": x[1] & ' ' & x[2],
      }
      newid = graphDB.insertID(
        sql"INSERT INTO nodes (tag, doc) VALUES ('person', ?)",
        $data)

    vritualId[(nActor, oldid)] = newid

  echo "rels"
  for x in sakilaDB.fastRows sql"SELECT * FROM film_actor fa":
    let 
      actorid = parseint x[0]
      filmid = parseint x[1]
      
    graphDB.exec(
      sql"INSERT INTO edges (tag, source, target, doc) VALUES ('acted_in', ?, ?, '{}')", 
      vritualId[(nActor, actorid)], 
      vritualId[(nFilm , filmid)]
    )

  echo "done"
  close sakilaDB
  close graphDB
