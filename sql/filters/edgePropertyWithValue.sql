-- key: string
-- collate: string
-- symb: string
-- val: string

(
  json_extract(edges.properties, {key})
  {collate} {symb} {val}
)