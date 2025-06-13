## converts sakila DB to graph form
## https://github.com/siara-cc/sakila_sqlite3/


import db_connector/db_sqlite
import std/[json, tables, strutils, paths]

import ../src/utils/other
import ../src/backend/model

# ---------------------------------

type
  Node = enum
    nFilm
    nActor

var vritualId: Table[(Node, int), int]

prepareDB Path "temp/sakila_graph.db"

let 
  sakilaDB    = openSqliteDB "temp/sakila.db"
  graphDB     = openSqliteDB "temp/sakila_graph.db"


echo "films"
for x in sakilaDB.fastRows sql"SELECT * FROM film f":
  let 
    oldid = parseint x[0]
    data = %*{
      "title": x[1],
    }
    newid = graphDB.insertID(
      sql"INSERT INTO nodes (__tag, __doc) VALUES ('movie',?)", 
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
      sql"INSERT INTO nodes (__tag, __doc) VALUES ('person', ?)",
      $data)

  vritualId[(nActor, oldid)] = newid

echo "rels"
for x in sakilaDB.fastRows sql"SELECT * FROM film_actor fa":
  let 
    actorid = parseint x[0]
    filmid = parseint x[1]
    
  graphDB.exec(
    sql"INSERT INTO edges (__tag, __head, __tail, __doc) VALUES ('acted_in', ?, ?, '{}')", 
    vritualId[(nActor, actorid)], 
    vritualId[(nFilm , filmid)]
  )

echo "done"
close sakilaDB
close graphDB
