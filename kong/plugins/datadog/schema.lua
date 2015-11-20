local ALLOWED_LEVELS = { "debug", "info", "notice", "warning", "err", "crit", "alert", "emerg" }

return {
  fields = {
    host = { type = "string", default = "127.0.0.1" },
    port = { type = "number", default = 8125 },
    key = { required = true, type = "string"},
    namespace = { type = "string", default = "kong" }
  }
}
