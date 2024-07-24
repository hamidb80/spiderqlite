import pretty
import query_language/parser

# TODO write == function
# TODO move it to test

let 
  multiline = parseSpQl """
    #user  u
      == 
        .name 
        |uname|
  """
  singleline = parseSpQl """
    #user  u
      == .name |uname|
  """


print multiline
print singleline
# assert multiline == singleline


let s = parseSpQl """
#user u
ask   u
ret 
  {}
    "sum"
    + 
      1 
      u
        .__id

    "wow"
    () if 1 2
"""

print s