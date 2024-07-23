import std/[json]

import ../bridge


const # ---------- tags
  
  userTag*     = parseTag "#user"
  dbTag*       = parseTag "#db"
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

  dbs_of_user* = """
    @owns     o
    #db       db
    #user     u
      == .name |uname|

    ASK       ^u>-o->db
    RET       db
  """

# ----- docs -------------------------------------

func initUserDoc*(name, passw: string): JsonNode = 
  %*{
    "name": name,
    "pass": passw
  }

func initDbDoc*(name: string): JsonNode = 
  %*{"name": name}

# ----------------------------------------------
