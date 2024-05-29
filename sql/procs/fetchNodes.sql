-- tag  : string
-- conds: string

SELECT 
  id, 
  tag, 
  properties
FROM 
  nodes
WHERE 
  tag = ? 
  [conds]