-- tag: string
-- properties: json
-- id: id

UPDATE 
  nodes 
SET 
  tag        = {tag}, 
  properties = {properties}
WHERE 
  id         = {id}