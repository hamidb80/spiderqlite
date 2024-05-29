-- tag: string
-- source: id
-- target: id
-- searchForProperties: string

(
  edges.tag = ? AND 
  (
    edges.target = ? OR 
    edges.source = ?
  ) 
  [searchForProperties]
)