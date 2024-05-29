import db_connector/db_sqlite


let
  dbPath = "play.db" 
  db     = open(dbPath, "", "", "")


close db