local BaseService = require "kong.cli.services.base_service"
local logger = require "kong.cli.utils.logger"
local IO = require "kong.tools.io"
local stringy = require "stringy"
local utils = require "kong.tools.utils"
local cjson = require "cjson"
local dao = require "kong.tools.dao_loader"

local Serf = BaseService:extend()

local SERVICE_NAME = "serf"
local LOG_FILE = "/tmp/"..SERVICE_NAME..".log"
local START_TIMEOUT = 5
local EVENT_NAME = "kong"

function Serf:new(configuration_value)
  local nginx_working_dir = configuration_value.nginx_working_dir

  self._parsed_config = configuration_value
  self._script_path = nginx_working_dir
                        ..(stringy.endswith(nginx_working_dir, "/") and "" or "/")
                        .."serf_event.sh"
  Serf.super.new(self, SERVICE_NAME, nginx_working_dir)
end

function Serf:prepare()
  local luajit_path = BaseService.find_cmd("luajit")
  
  local script = [[
#!/bin/sh
JSON_TOPIC_RAW=`cat` # Read from stdin
JSON_TOPIC_RAW=${JSON_TOPIC_RAW//\\/\\\\} # \ 
JSON_TOPIC_RAW=${JSON_TOPIC_RAW//\//\\\/} # / 
JSON_TOPIC_RAW=${JSON_TOPIC_RAW//\'/\\\'} # ' (not strictly needed ?)
JSON_TOPIC_RAW=${JSON_TOPIC_RAW//\"/\\\"} # " 
JSON_TOPIC_RAW=${JSON_TOPIC_RAW//   /\\t} # \t (tab)
JSON_TOPIC_RAW=${JSON_TOPIC_RAW//
/\\\n} # \n (newline)
JSON_TOPIC_RAW=${JSON_TOPIC_RAW//^M/\\\r} # \r (carriage return)
JSON_TOPIC_RAW=${JSON_TOPIC_RAW//^L/\\\f} # \f (form feed)
JSON_TOPIC_RAW=${JSON_TOPIC_RAW//^H/\\\b} # \b (backspace)

PAYLOAD=""

if [ $SERF_EVENT = "user" ]; then
  PAYLOAD=$JSON_TOPIC_RAW
else
  PAYLOAD="{\\\"type\\\":\\\"${SERF_EVENT}\\\",\\\"entity\\\":\\\"${JSON_TOPIC_RAW}\\\"}"
fi

COMMAND='require("kong.tools.http_client").post("http://127.0.0.1:]]..self._parsed_config.admin_api_port..[[/cluster/events/", "'${PAYLOAD}'", {["content-type"] = "application/json"})'

echo $COMMAND | ]]..luajit_path..[[
]]
  local _, err = IO.write_to_file(self._script_path, script)
  if err then
    return false, err
  end

  -- Adding executable permissions
  local res, code = IO.os_execute("chmod +x "..self._script_path)
  if code ~= 0 then
    return false, res
  end

  return true
end

function Serf:_autojoin()
  if self._parsed_config.cluster["auto-join"] then 
    local dao_factory = dao.load(self._parsed_config)
    local nodes, err = dao_factory.nodes:find_by_keys({status = "alive"})
    if err then
      return false, tostring(err)
    else
      if #nodes == 0 then
        logger:warn("No nodes found to auto-join")
      else
        local joined
        for _, v in ipairs(nodes) do
          local _, err = self:invoke_signal("join", {v.address})
          if err then
            logger:warn("Cannot join "..v.address)
          else
            logger:info("Successfully auto-joined "..v.address)
            joined = true
            break
          end
        end
        if not joined then
          return false, "Could not join the existing cluster"
        end
      end
    end
  end
  return true
end

function Serf:start()
  if self:is_running() then
    return nil, SERVICE_NAME.." is already running"
  end

  local cmd, err = Serf.super._get_cmd(self)
  if err then
    return nil, err
  end

  -- Prepare arguments
  local cmd_args = {}
  setmetatable(cmd_args, require "kong.tools.printable")
  for k, v in pairs(self._parsed_config.cluster) do
    if type(v) ~= "table" and (type(v) == "boolean" or stringy.strip(v) ~= "") then
      cmd_args["-"..k] = v
    end
  end
  cmd_args["-auto-join"] = nil
  cmd_args["-log-level"] = "err"
  cmd_args["-node"] = utils.get_hostname().."_"..self._parsed_config.cluster.bind
  cmd_args["-event-handler"] = "member-join,member-leave,member-failed,member-update,member-reap,user:"..EVENT_NAME.."="..self._script_path

  local str_cmd_args = tostring(cmd_args)

  -- Attach tags
  if self._parsed_config.cluster.tags then
    for k, v in pairs(self._parsed_config.cluster.tags) do
      if stringy.strip(v) ~= "" then
        str_cmd_args = str_cmd_args.." -tag="..k.."="..v
      end
    end
  end

  local res, code = IO.os_execute("nohup "..cmd.." agent "..str_cmd_args.." > "..LOG_FILE.." 2>&1 & echo $! > "..self._pid_file_path)
  if code == 0 then

    -- Wait for process to start, with a timeout
    local start = os.time()
    while not (string.match(IO.read_file("/tmp/serf.log"), "running") or (os.time() > start + START_TIMEOUT)) do
      -- Wait
    end

    if self:is_running() then
      logger:info(string.format([[serf ..............%s]], str_cmd_args))

      -- Auto-Join nodes
      return self:_autojoin()
    else
      -- Get last error message
      local parts = stringy.split(IO.read_file(LOG_FILE), "\n")
      return nil, "Could not start serf: "..string.gsub(parts[#parts - 1], "==> ", "")
    end
  else
    return nil, res
  end
end

function Serf:invoke_signal(signal, args, no_rpc)
  if not self:is_running() then
    return nil, SERVICE_NAME.." is not running"
  end

  local cmd, err = Serf.super._get_cmd(self)
  if err then
    return nil, err
  end

  if not args then args = {} end
  setmetatable(args, require "kong.tools.printable")
  local res, code = IO.os_execute(cmd.." "..signal.." "..(no_rpc and "" or "-rpc-addr="..self._parsed_config.cluster["rpc-addr"]).." "..tostring(args), true)
  if code == 0 then
    return res
  else
    return false, res
  end
end

function Serf:event(t_payload)
  local args = {
    ["-coalesce"] = false,
    ["-rpc-addr"] = self._parsed_config.cluster["rpc-addr"]
  }
  setmetatable(args, require "kong.tools.printable")

  local encoded_payload = cjson.encode(t_payload)
  if string.len(encoded_payload) > 512 then
    -- Serf can't send a payload greater than 512 bytes
    return false, "Encoded payload is "..string.len(encoded_payload).." and it exceeds the limit of 512 bytes!"
  end 

  return self:invoke_signal("event "..tostring(args).." kong", {"'"..encoded_payload.."'"}, true)
end

function Serf:stop()
  local _, err = self:invoke_signal("leave")
  if err then
    return false, err
  else
    Serf.super.stop(self)
  end
end

return Serf