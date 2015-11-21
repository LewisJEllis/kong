return {
  fields = {
    host = { type = "string", default = "localhost" },
    port = { type = "number", default = 8125 },
    namespace = { type = "string", default = "kong" },
    timeout = { default = 10000, type = "number" }
  }
}
