import std/[json, os]

type
  ToDo = object
    desc:    string
    created: int64



proc addTodo(t: ToDo) = 
  db.exec """
    #task  t
    INSERT t
  """