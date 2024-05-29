-- key: str
-- val: json

UPDATE 
  nodes 
SET 
  properties = json_set(properties, {key}, {val}) 
WHERE 
  id         = {id}