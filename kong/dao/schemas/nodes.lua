return {
  name = "Node",
  primary_key = {"id"},
  fields = {
    id = { type = "id", dao_insert_value = true },
    created_at = { type = "timestamp", dao_insert_value = true },
    address = { type = "string", unique = true, queryable = true, required = true },
    name = { type = "string", unique = true, queryable = true, required = true },
    tags = { type = "table" },
    status = { type = "string", queryable = true, required = true }
  }
}
