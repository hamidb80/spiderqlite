import std/[json, strformat]

import ../bridge


func `$`(t: Tag): string = t.string

const # ---------- tags
  
  userTag*     = parseTag "#user"
  dbTag*       = parseTag "#db"
  authTag*     = parseTag "#auth"
  backupTag*   = parseTag "#backup"
  
  ownsTag*       = parseTag "@owns"
  isBackupOfTag* = parseTag "@is_backup_of"


const # ----------- local aliases

  user   = userTag
  db     = dbTag
  auth   = authTag

  owns   = ownsTag


const # ---------- queries

  get_user_by_name* = fmt"""
    #{user}  u
      == .name |uname|
    ASK u
    RET u
  """

  all_users* = fmt"""
    #{user} u
    ASK     u
    RET     u
  """

  dbs_of_user* = fmt"""
    @{owns}     o
    #{db}       db
    #{user}     u
      == .name |uname|

    ASK       ^u>-o->db
    RET       db
  """

# ----- docs -------------------------------------

func initUserDoc*(name, passw: string, isAdmin: bool): JsonNode = 
  %*{
    "is_admin": isAdmin,
    "name"    : name,
    "pass"    : passw,
  }

func initDbDoc*(name: string): JsonNode = 
  %*{
    "name": name,
  }

# ----------------------------------------------
