import std/[json]

import ../query_language/parser
import ../bridge


const 
  userTag* = parseTag "#user"
  
  get_user_by_name* = """
    #user  u
      == 
        .name 
        |uname|
    ASK u
    RET u
  """

  all_users* = """
    #user u
    ASK   u
    RET   u
  """
  
# ----------------------------------

func initUserDoc*(name, passw: string): JsonNode = 
  %*{
    "name": name,
    "pass": passw
  }