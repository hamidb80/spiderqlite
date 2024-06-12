import std/[tables, strutils, sequtils, math, algorithm]
import ./other

type
  # Matrix[T]   = object
  #   data: seq[seq[T]]

  GraphOfList*[T]    = object
    names: seq[string]
    rels:  Table[Slice[string], seq[T]]


# func width*  (m: Matrix): Natural = 
#   len m.data[0]

# func height* (m: Matrix): Natural = 
#   len m.data

# func size*   (m: Matrix): Natural = 
#   m.width * m.height

# func `[]`*[T](m: Matrix[T], i, j: Natural): T = 
#   ## ij
#   ## 00 01 02
#   ## 10 11 12
#   ## 20 21 22

#   m.data[i][j]

func addEdge[T](g: var GraphOfList[T], a, b: string, c: T) {.inline.} = 
  let key = a .. b
  
  if key notin g.rels:
    g.rels[key] = @[]
  
  g.rels[key].add c

func addNodeIfNotExists(g: var GraphOfList, name: string) {.inline.} = 
  if name notin g.names:
    g.names.add name

func addNode*(g: var GraphOfList, name: string) {.inline.} = 
  g.addNodeIfNotExists name

func addConn*[T](g: var GraphOfList[T], a, b: string, c: T) = 
  g.addNode a
  g.addNode b
  g.addEdge a, b, c


func nodesLen*[T](g: GraphOfList[T]): Natural = 
  g.names.len

func distinctEdges*[T](g: GraphOfList[T]): Natural = 
  g.rels.len

func allEdges*[T](g: GraphOfList[T]): Natural = 
  for v in values g.rels:
    result.inc v.len

func `$`*(g: GraphOfList): string = 
  let namesLen = g.names.mapit(it.len)
  let maxNamesLen = namesLen.max

  << '_'.repeat maxNamesLen
  << '|'
  
  for b in g.names:
    << b
    << ' '.repeat maxNamesLen - b.len
    << '|'
  << '\n'

  
  for a in g.names:
    << a
    << ' '.repeat maxNamesLen - a.len
    << '|'

    for b in g.names:
      let 
        key = a .. b
        n   = g.rels.getOrDefault(key).len
        s   = $n

      << s
      << ' '.repeat maxNamesLen - s.len
      << '|'

    << '\n'  