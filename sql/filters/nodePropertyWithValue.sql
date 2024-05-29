-- key: string
-- collate: string
-- symb: string
-- val: string

(
  json_extract(nodes.properties, {key})
  {collate} {symb} {val}
)