local lsyslog = require "lsyslog"
local cjson = require "cjson"
local Statsd = require "kong.plugins.datadog.stastd"

local ngx_log = ngx.log
local ngx_timer_at = ngx.timer.at
local ngx_socket_udp = ngx.socket.udp


local _M = {}

local function send_statsd_message(conf, message)
local stastd = Statsd.new(conf)

end


local function log(conf, message, pri)
  local stastd = Statsd.new(conf)
  local api_name = message.api.name
  -- send size gauge
  local stat = api_name..".request.size"
  stastd.gauge(stat, message.request.size)
  stat = api_name..".response.size"
  stastd.gauge(stat, message.response.size)
  stat = api_name..".request.count"
  stastd.counter(stat, 1)
  stastd.close_socket()
end

function _M.execute(conf, message)
  local ok, err = ngx_timer_at(0, log, conf, message)
  if not ok then
    ngx_log(ngx.ERR, "failed to create timer: ", err)
  end
end

return _M
