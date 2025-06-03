import std/[sequtils]

type
  Mat*[T] = object
    data*: seq[seq[T]]
  

func height*(m: Mat): Natural = 
  m.data.len

func width*(m: Mat): Natural = 
  if 0 == m.height: 0
  else:             m.data[0].len

func initMatrixOf*[T](n: Natural): Mat[T] = 
  discard

func `[]`*[T](m: Mat[T], i, j: int): T = 
  m.data[i][j]

func `[]`*[T](m: var Mat[T], i, j: int): var T = 
  m.data[i][j]

func addColumn*[T](m: var Mat[T], val: T) = 
  for row in mitems m.data:
    add row, val

func addRow*[T](m: var Mat[T], val: T) = 
  add m.data, val.repeat m.width
