local lsyslog = require "lsyslog"
local cjson = require "cjson"
local statsd_logger = require "kong.plugins.datadog.statsd_logger"

local ngx_log = ngx.log
local ngx_timer_at = ngx.timer.at
local ngx_socket_udp = ngx.socket.udp


local _M = {}

local function log(premature, conf, message)
  local inspect = require "inspect"
  print(inspect(conf))
  print(inspect(statsd_logger))
  local logger, err = statsd_logger:new(conf)
  if err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end
  local api_name = message.api.name
  -- send size gauge
  local stat = api_name..".request.size"
  logger:gauge(stat, message.request.size, 1)
  stat = api_name..".response.size"
  logger:gauge(stat, message.response.size, 1)
  stat = api_name..".request.count"
  logger:counter(stat, 1, 1)
  logger:close_socket()
end

function _M.execute(conf, message)
  local ok, err = ngx_timer_at(0, log, conf, message)
  if not ok then
    ngx_log(ngx.ERR, "failed to create timer: ", err)
  end
end

return _M
