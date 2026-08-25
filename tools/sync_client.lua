#!/usr/bin/env lua

local endpoint = arg[1]
local bookmarks = arg[2]
local history = arg[3]
local settings = arg[4]

-- The auth token is passed via environment variable, never on the command line,
-- so it is not visible to other local processes (ps, /proc/<pid>/cmdline).
local token = os.getenv("OBROWSER_SYNC_TOKEN") or ""

if not endpoint or token == "" then os.exit(2) end

if not endpoint:match("^https://") then
  io.stderr:write("Refusing sync: endpoint must use HTTPS (" .. tostring(endpoint) .. ").\n")
  os.exit(2)
end

local function read(path)
  local f = io.open(path, "r")
  if not f then return "" end
  local c = f:read("*a")
  f:close()
  return c
end

local function json_escape(s)
  s = s or ""
  local out = {'"'}
  for i = 1, #s do
    local b = s:byte(i)
    if b == 34 then out[#out + 1] = '\\"'
    elseif b == 92 then out[#out + 1] = '\\\\'
    elseif b == 10 then out[#out + 1] = '\\n'
    elseif b == 13 then out[#out + 1] = '\\r'
    elseif b == 9 then out[#out + 1] = '\\t'
    elseif b < 32 then out[#out + 1] = string.format('\\u%04x', b)
    else out[#out + 1] = string.char(b)
    end
  end
  out[#out + 1] = '"'
  return table.concat(out)
end

-- Safely quote a single argument for the shell using single quotes.
local function sh_quote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local payload = '{"bookmarks":' .. json_escape(read(bookmarks))
  .. ',"history":' .. json_escape(read(history))
  .. ',"settings":' .. json_escape(read(settings)) .. '}'

local payfile = os.tmpname()
local pf = io.open(payfile, "w")
if not pf then os.exit(3) end
pf:write(payload)
pf:close()

local auth_header = "Authorization: Bearer " .. token
local cmd = "curl -fsSL -X POST -H " .. sh_quote(auth_header)
  .. " --data @" .. sh_quote(payfile)
  .. " " .. sh_quote(endpoint) .. " >/dev/null"
local ok = os.execute(cmd)
os.remove(payfile)
if ok == true or ok == 0 then
  os.exit(0)
end
os.exit(3)
