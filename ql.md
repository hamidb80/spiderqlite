
## Query Language
The query language is heavily inspired by Cypher ([query language of Neo4j](https://neo4j.com/docs/cypher-cheat-sheet/5/auradb-enterprise/)), you can think of it as a mix of Lisp and SQL and Cypher. 

### Syntax

#### comment
One line string that starts with `--`
```sql
-- this is comment 🐣
```

#### numbers
##### int
only decimal integers are supported for now.
`321`

##### float
normal floating point number:
`3.1412`

#### string
normal string literal:
`"string"`

#### variable
An ident between 2 `|`s:  
`|varname|`

#### ident
anything that starts with letters, or cannot be matched with other rules :D.

#### Nesting and passing parameters
Nesting can be done in 2 ways:

##### 1. indentation
```sql
AND
  a
  2
```

##### 2. in sequence 
```sql
AND a 2
```

**note**: the latter is used for simple expressions/statements. Most of the times you should go with indentations. 


#### Prefix
pattern
```sql
OPERATOR right_hand_side
-- or
OPERATOR
  right_hand_side
```

operators:
- `NOT`: negates
- `$`:   converts to string


#### Infix 
usage:
```sql
OPERATOR left_hand_side right_hand_side
-- or
OPERATOR
  left_hand_side
  right_hand_side
```

operators:
- `-`, `+`, `*`, `/`: common math operations
- `%`: modulo
- `<`, `<=`, `==`, `!=`, `=>`, `>`, `IS`, `ISNOT`: comparison operators
- `||`: string concatination
- `LIKE`: string match
- `AND`, `OR`, `NAND`, `NOR`, `XOR`: Logical operators


#### Defining identifier
##### Node 
```sql
#tag nickname
  ...
```

##### Edge 
Same as the way you define a node, the only difference is that you put `@` instead of `#`. 

#### Alias
You may define alias for repeative expressions or readability. you can think of it as `#define` macro in C.
```sql
AS
  ident1
  expr1

  ident2
  expr2

  ...
```

e.g.
```sql
AS 
  age
  - 2024 p.birth.year 
```

you can use this alias later in your query, like:
```sql
RETURN 
  {}
    "is_adult"
    >=
      age
      18
```

#### Function Call 
```sql
() FUNCTION arg1 arg2 ...
-- or
() 
  FUNCTION 
  arg1 
  arg2 
  ...
```

##### Special functions
here's are sugar for some functions with their equivalent SQLite function name.
- `>>` : `json`
- `{}` : `json_object`
- `{}.`: `json_group_object`
- `[]` : `json_array`
- `[].`: `json_group_array`


#### USE, TEMPLATE
```sql
USE      template_name
-- or 
TEMPLATE template_name
```

#### PARAMS, PARAMETERS
```sql
PARAMS      p1 p2 ...
-- or
PARAMETERS  p1 p2 ...
``` 

#### ASK, MATCH, FROM
```sql
ASK node
-- or
ASK edge
-- or
ASK
  relation_1
  relation_2
  ...
```

##### relation
```sql
a>-x->b
a<-x-<b
```

```sql
a<-x-<b<-y-<c
-- is equivalent to
a<-x-<b
b<-y-<c
```


#### TAKE, SELECT, RETURN, RET
```sql
TAKE expr
-- or
TAKE
  expr
```

#### Field access 
##### standard
```sql
.field
.field.subfield
```

##### sugar
```sql
name.field
name.field.subfield
```

converts to:

```sql
name
  .field
name
  .field.subfield
```

#### GROUP, GROUPE_BY
same as `GROUP BY` in SQL.

```sql
GROUP ident
-- or
GROUP_BY ident
```

#### HAVING
same as `HAVING` in SQL.

```sql
HAVING cond
-- or 
HAVING
  cond
```

#### ORDER, ORDER_BY
same as `ORDER BY` in SQL but only idents.
```sql
ORDER     ident_1 ident_2 ... 
-- or
ORDER_BY  ident_1 ident_2 ...
```

#### SORT, SORT_BY
corresponding direction `ASC`(ascending) or `DESC`(descending) for each ident that is in `ORDER` clause.
```sql
SORT     dir_for_ident_1 dir_for_ident_2 ... 
-- or
SORT_BY 
  dir_for_ident_1 
  dir_for_ident_2 
  ... 
```

#### LIMIT
same as `LIMIT` in SQL.
```sql
LIMIT integer
```

#### OFFSET
same as `OFFSET` in SQL.
```sql
OFFSET integer
```

#### CASE, WHEN, ELSE
same as `CASE` in SQL.

```sql
CASE
  WHEN 
    >= amount 10000 
    "Large Order"
  WHEN 
    < amount 10000
    "Small Order"
  ELSE
    "N/A"
```

#### IF
same as [`IFF` in SQL](
https://www.sqlitetutorial.net/sqlite-functions/sqlite-iif/).
```sql
IF cond true_expr false_expr
-- or
IF 
  cond 
  true_expr 
  false_expr
```

### Semantic

#### Context
A context object is used to resolve variables in SpQL queries.

#### Query Strategy File
a file defining query patterns.

```toml
[[strategies]]
key        = "single-edge-node-head"
parameters = "a b c"
pattern    = "^a>-c->b"
selectable = "a b c"
sql        = '''
  SELECT 
    |select_fields|
  FROM
    nodes a
  INNER JOIN 
    edges c,
    nodes b
  ON
    |check_conds c|     AND
    |check_rels c a b|
  WHERE 
    |check_conds a| AND
    |check_conds b| 

  |group_statement|
  |having_statement|
  |order_statement|
  |limit_statement|
  |offset_statement|
'''
```

#### Matching by topology

##### query for single node
returns all of the nodes with tag `person`
```sql
#person p
ASK     p
RETURN  p
```

##### query for relation [without cond on edge]
```sql
#movie    m
@acted_in a
#person   p
  ==
    .name
    "Davood Mir-Bagheri"

ASK 
  p>-+a->m

RETURN 
  {}
    "person"
    p

    "movies"
    [].
      m
```


##### query for relation [with cond on edge]

```sql
@acted_in i->a->j
  >
    i.age
    j.age
```

- XXX: won't be supported since it is not 
how you should write graph queries i.e. it is valid in relational world 
but not Graph databases.


#### Using template
```sql
#person    p
#movie     m
#acted_in  a

USE    single-edge-node-head
PARAMS p m a
```

#### Defining Object Model
##### Guards [TODO]
if you define guard for your database, you will get error when the object model does not match with it on update or delete.

```sql
~Sex
  "male"
  "female"

#movie   m
  .title     string
  .published unixtime

#person  p
  .name  -- nested
    .first string
    .last  string
  
  .nicknames  string[] -- array

  .birth     unixtime
  .sex       Sex

  .has_diploma? boolean -- optional  
```

### Examples
more examples in `tests/defs`.
