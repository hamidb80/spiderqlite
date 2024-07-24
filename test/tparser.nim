
when isMainModule:
  import pretty

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
  assert multiline == singleline
