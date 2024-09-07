> Truth saves you even though you're afraid of it, and mendacity destroys you even though you don't see any danger -- Imam Ali

# SpQL 🕷
*SpQL* is graph abstraction over SQL. 
Making SQL frictionless by removing the pain of schema changes and bringing the joy of graph theory.

<p align="center">
  <img src="./assets/logo-cc.svg" alt="spiderQlite Logo" width="z00px">
</p>

## Initial Motivation
The author found the SQL tables too rigid, and felt something is missing in document-based databases like MongoDB and CouchDB which makes them unconventional to use (not mentioning their wierd query language). At that time, graph databases like Neo4j and ArangoDB made more sense to him. Because his projects were mostly small size, using mentioned databases is not worth it since they require lots of RAM and computational power.

He dreamed of something that is compatible to SQL as it can be used upon SQLite.

## Terminology
Spider (🕷) is well-known instinct which walks on his network (🕸). The network is metaphore for *graph*. Since its actions/queries is converted to SQL, its name may be mix of these 2 words; Hence Sp<sub>ider</sub>QL or SpQL.


## Usage
### as Library
Just converts `spql` to `sql` language.

### as Server
It aims to bring best of SQLite, Neo4j, CouchDB together.

#### Front end [TODO]

#### Config
To use as server, it is mandatory to provide a config file which is written in [TOML](https://toml.io/) format. You can you the one that use for development or you write your own. The values in config file can be overwritten by environment variables or flags which are passed as command line arguemnts.

You can look `src/config.nim` to see full list of available configs, but for introduction let's take a look at few of them.

```nim
server: ServerConfig(
  host:  v(ctx, "--host", "SPQL_HOST", "server.host", Host),
  port:  v(ctx, "--port", "SPQL_PORT", "server.port", Port),
)
```

The above code says it first looks at if there is any CLI parameter with key of `--host`, if not, look for `SPQL_HOST` environment variable, if can't find it, then look at `server.host` in config file. If still can't find the value, it throws error, saying the config value is missing.

### Integrations
#### Python Driver :: SpqlClient
... 

## Concepts
### Entities
In graph theory, there are 2 types of entities: nodes and edges.

#### Node
A node is something that holds data. 
Here's the internal structure of a node:

| id: `int` | tag: `string` | data: `JSON` |
|-----------|---------------|--------------|
| 1         | person        | {"name": "Farajollah Salahshoor"} |
| 2         | person        | {"name": "Mostafa Zamani"} |
| 3         | movie         | {"title": "Prophet Joseph"} |

#### Edge
An edge is somehting that relates source node to the target node. 
Tt may contain data.   
Here's the internal structure of an edge:

| id: int | tag: string | data: JSON | source: int | target: int |
|---------|-------------|------------|-------------|-------------|
| 1       | directed_by | {}         | 3           | 1           |
| 2       | acted_in    | {}         | 2           | 3           |

The above edge shows following relations:
- ndoe 3 is `directed by` node 1 
- node 2 acted in node 3 

### Tag
A tag is similar to ***table name*** in SQL or ***collection*** in document-based databases.
It is indexed and efficient to query about.

## Query Language
see `ql.md`

## Indexes
...

## Other
Here are some of the things that I found worth mentioning.

### links
- https://www.delphitools.info/2021/06/17/sqlite-as-a-no-sql-database/
- https://www.sqlitetutorial.net/sqlite-index/sqlite-drop-index/
- https://database.guide/list-indexes-in-sqlite-database/
- https://stackoverflow.com/questions/12526194/mysql-inner-join-select-only-one-row-from-second-table
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
- https://wiki.postgresql.org/wiki/Sample_Databases
- https://www.sqlitetutorial.net/sqlite-sample-database/
- https://github.com/siara-cc/sakila_sqlite3/
- https://antonz.org/sqlean-define/

## credits
- https://www.svgrepo.com/svg/383453/spider-web
- https://www.svgrepo.com/svg/471314/database-01

## Footnotes
> I don't have brain to write more SQLs anymore -- *me*

> Friends don't let friends write SQL -- *MongoDB ads*, [WTF](https://www.linkedin.com/pulse/friends-dont-let-use-mongodb-constantin-a-alexander)

## Mascot
![SpiderQL Mascot](./assets/mascot.png)
