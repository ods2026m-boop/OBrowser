#!/usr/bin/env lua

local path = arg[1]
local endpoint = arg[2]
local token = arg[3]
if not path or not endpoint or not token then os.exit(2) end

-- Safely quote a single argument for the shell using single quotes.
local function sh_quote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local auth_header = "Authorization: Bearer " .. token
local cmd = "curl -fsSL -X POST -H " .. sh_quote(auth_header)
  .. " --data-binary @" .. sh_quote(path)
  .. " " .. sh_quote(endpoint) .. " >/dev/null"
local ok = os.execute(cmd)
if ok == true or ok == 0 then os.exit(0) end
os.exit(3)
