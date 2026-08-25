#!/usr/bin/env lua

local manifest_url = arg[1]
local channel = arg[2] or "stable"
local current = arg[3] or "0.1.0"

if not manifest_url or manifest_url == "" then
  os.exit(2)
end

local temp = os.tmpname()
local cmd = string.format("curl -fsSL %q -o %q", manifest_url, temp)
if os.execute(cmd) ~= true and os.execute(cmd) ~= 0 then
  os.exit(3)
end

local f = io.open(temp, "r")
if not f then
  os.exit(4)
end
local body = f:read("*a")
f:close()
os.remove(temp)

local latest = body:match('"' .. channel .. '"%s*:%s*{[^}]-"version"%s*:%s*"([^"]+)"') or current
local notes = body:match('"' .. channel .. '"%s*:%s*{[^}]-"notes"%s*:%s*"([^"]*)"') or ""
local url = body:match('"' .. channel .. '"%s*:%s*{[^}]-"url"%s*:%s*"([^"]*)"') or ""

local function cmp(a,b)
  local function split(v)
    local t = {}
    for n in v:gmatch("%d+") do table.insert(t, tonumber(n)) end
    return t
  end
  local aa, bb = split(a), split(b)
  for i=1,math.max(#aa,#bb) do
    local x,y = aa[i] or 0, bb[i] or 0
    if x>y then return 1 elseif x<y then return -1 end
  end
  return 0
end

print("latest_version=" .. latest)
print("notes=" .. notes)
print("url=" .. url)
print("update_available=" .. tostring(cmp(latest, current) > 0))
