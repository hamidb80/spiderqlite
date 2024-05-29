-- source: id
-- target: id

DELETE 
FROM 
  edges 
WHERE 
  source = {source} OR 
  target = {target}