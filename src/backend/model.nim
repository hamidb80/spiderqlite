import std/[json, strformat, os, paths]

import ../utils/other
import ./config
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

  USER   = userTag
  DB     = dbTag
  # auth   = authTag

  OWNS   = ownsTag


const # ---------- queries

  get_user_by_name* = fmt"""
    #{USER}  u
      == .name |uname|
    ASK u
    RET u
  """

  all_users* = fmt"""
    #{USER} u
    ASK     u
    RET     u
  """

  dbs_of_user* = fmt"""
    @{OWNS}     o
    #{DB}       db
    #{USER}     u
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

proc initDB*(fpath: Path) = 
  initDbSchema openSqliteDB fpath

proc prepareDB*(fpath: Path) = 
  if not fileExists fpath: 
    initDB fpath

proc preapreStorage*(config: AppConfig) = 
  discard existsOrCreateDir config.storage.appDbFile.string.splitPath.head
  discard existsOrCreateDir config.storage.usersDbDir.string
  discard existsOrCreateDir config.storage.backupdir.string

  prepareDB config.storage.appDbFile

# ----------------------------------------------
