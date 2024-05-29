-- tag   : string
-- source: id
-- target: id

DELETE 
FROM 
  edges 
WHERE 
  tag    = {tag}    AND 
  source = {source} AND 
  target = {target}
