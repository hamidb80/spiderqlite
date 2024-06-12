type
  Mat*[T] = object
    data*: seq[seq[T]]
  

func width*(m: Mat): Natural = 
  m.data[0].len

func height*(m: Mat): Natural = 
  m.data.len

func initMatrixOf*[T](n: Natural): Mat[T] = 
  discard

func `[]`*[T](m: Mat[T], i, j: int): Natural = 
  m.data[i][j]
