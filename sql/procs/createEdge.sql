-- tag   : string
-- props : json
-- source: id
-- target: id

INSERT INTO 
  edges (
    tag,
    properties,
    source,
    target
  ) 
VALUES 
  (
    {tag},
    {props},
    {source},
    {target}
  )