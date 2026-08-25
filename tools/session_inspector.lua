#!/usr/bin/env lua

local function read_file(path)
  local file, err = io.open(path, "r")
  if not file then
    return nil, err
  end
  local content = file:read("*a")
  file:close()
  return content
end

local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function parse_session(content)
  local data = {
    active_index = 0,
    count = 0,
    tabs = {}
  }

  for line in content:gmatch("[^\r\n]+") do
    local key, value = line:match("^([^=]+)=(.*)$")
    if key and value then
      key = trim(key)
      value = trim(value)
      if key == "active_index" then
        data.active_index = tonumber(value) or 0
      elseif key == "count" then
        data.count = tonumber(value) or 0
      else
        local index = key:match("^tab%-(%d+)$")
        if index then
          data.tabs[tonumber(index) + 1] = value
        end
      end
    end
  end

  return data
end

local function usage()
  io.stderr:write("Usage: lua tools/session_inspector.lua <session.ini>\n")
  os.exit(1)
end

if #arg ~= 1 then
  usage()
end

local session_path = arg[1]
local content, err = read_file(session_path)
if not content then
  io.stderr:write("Failed to read session: " .. tostring(err) .. "\n")
  os.exit(2)
end

local session = parse_session(content)
print("Session file: " .. session_path)
print("Active index: " .. session.active_index)
print("Saved count : " .. session.count)
print("Tabs:")

local has_tabs = false
for i = 1, math.max(#session.tabs, session.count) do
  local uri = session.tabs[i]
  if uri and uri ~= "" then
    local marker = (i - 1 == session.active_index) and "*" or " "
    print(string.format(" %s [%d] %s", marker, i - 1, uri))
    has_tabs = true
  end
end

if not has_tabs then
  print("  (none)")
end
