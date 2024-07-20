# S<sub>pider</sub>QL

S<sub>pider</sub>QL or *SpQL* for short, is:
1. query abstraction library which aims to make SQL as frictionless as possible
2. simple SQLite manager server

<p align="center">
  <img src="./assets/logo-cc.svg" alt="spiderQlite Logo" width="z00px">
</p>

## Motivation
The author found the SQL tables too rigid, and felt something is missing in document-based databases like MongoDB and CouchDB which makes them unconventional to use. At the same time, graph databases like Neo4j and ArangoDB made more sense to him. Because his projects are mostly small, using mentioned databases is not worth it since they require lots of RAM and computational power.

At this point, he dreamt of something that is compatible to SQL as it can be put upon SQLite; and SpQL is found!

## Terminology
Spider is well-known instinct which walks on his network (🕸). The network is metaphore for *graph*. 

Since this library works with SQL, there must be SQL in the name. 

## Usage
### as Library
Just converting `spql` to `sql` format.

### as Server
It aims to bring best of SQLite, Neo4j, CouchDB together.

#### Config

## Query Language
### Examples
see examples in ...


## What I Found along the way
### links
- https://www.delphitools.info/2021/06/17/sqlite-as-a-no-sql-database/
- https://www.sqlitetutorial.net/sqlite-index/sqlite-drop-index/
- https://database.guide/list-indexes-in-sqlite-database/
- https://stackoverflow.com/questions/12526194/mysql-inner-join-select-only-one-row-from-second-table
- https://neo4j.com/docs/cypher-manual/current/functions/aggregating/
- https://sqlite.org/json1.html
- https://github.com/Nhogs/popoto

### Inspirations
- https://github.com/arturo-lang/grafito/
- https://github.com/webbery/gqlite
- https://github.com/dpapathanasiou/simple-graph
- CouchDB
- Neo4j
- ArangoDB
- https://github.com/krisajenkins/yesql

### Sample Databases
- https://www.sqlitetutorial.net/sqlite-sample-database/
- https://github.com/siara-cc/sakila_sqlite3/
- https://antonz.org/sqlean-define/


## credits
- https://www.svgrepo.com/svg/383453/spider-web
- https://www.svgrepo.com/svg/471314/database-01
