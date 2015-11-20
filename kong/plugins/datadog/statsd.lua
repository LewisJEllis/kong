local setmetatable = setmetatable

local function create_statsd_message(self, stat, delta, kind, sample_rate)
  
  local rate = ""
  if sample_rate and sample_rate ~= 1 then 
    rate = "|@"..sample_rate 
  end
  
  local message = {
    self.namespace,
    stat,
    ":",
    delta,
    "|",
    kind,
    rate
  }
  return table.concat(message, "")
end


local stasd_mt = {}
function stasd_mt:new(conf)
  
  local sock = ngx.socket.udp()
  sock:settimeout(conf.timeout)
  local ok, err = sock:setpeername(conf.host, conf.port)
  
  local stasd = {
    host = conf.host,
    port = conf.port,
    socket = sock,
    namespace = conf.namespace
  }
  return setmetatable(stasd, stasd_mt)
end

function stasd_mt:close_socket()
  local ok, err = self.sock:close()
  if not ok then
    ngx.log(ngx.ERR, "failed to close connection from "..self.host..":"..tostring(self.port)..": ", err)
    return
  end
end

function stasd_mt:send_statsd(stat, delta, kind, sample_rate)
  local udp_message = create_statsd_message(stat, delta, kind, sample_rate)
  local ok, err = sock:send(udp_message)
  if not ok then
    ngx_log(ngx.ERR, "failed to send data to "..self.host..":"..tostring(self.port)..": ", err)
  end
end

function stasd_mt:gauge(stat, value, sample_rate)
  return self:send_statsd(stat, value, "g", sample_rate)
end

function stasd_mt:counter(stat, value, sample_rate)
  return self:send_statsd(stat, value, "c", sample_rate)
end

function stasd_mt:timer(stat, ms)
  return self:send_statsd(stat, ms, "ms")
end

function stasd_mt:histogram(stat, value)
  return self:send_statsd(stat, value, "h")
end

function stasd_mt:meter(stat, value)
  return self:send_statsd(stat, value, "m")
end

function stasd_mt:set(stat, value)
  return self:send_statsd(stat, value, "s")
end

return stasd_mt
