import std/[json]

import ../bridge


const # ---------- tags
  
  userTag*     = parseTag "#user"
  databaseTag* = parseTag "#db"
  authTag*     = parseTag "#auth"
  
  ownsTag*     = parseTag "@owns"
  forTag*      = parseTag "@for"


const # ---------- queries

  # schema = """ """

  get_user_by_name* = """
    #user  u
      == .name |uname|
    ASK u
    RET u
  """

  all_users* = """
    #user u
    ASK   u
    RET   u
  """
  
# ----- docs -------------------------------------

func initUserDoc*(name, passw: string): JsonNode = 
  %*{
    "name": name,
    "pass": passw
  }

func initDbDoc*(): JsonNode = 
  %*{}

