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

local function write_file(path, data)
  local file, err = io.open(path, "w")
  if not file then
    return nil, err
  end
  file:write(data)
  file:close()
  return true
end

local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function parse_ini(content)
  local entries = {}
  local current = nil

  for line in content:gmatch("[^\r\n]+") do
    local section = line:match("^%[([^%]]+)%]$")
    if section then
      current = { section = section }
      table.insert(entries, current)
    else
      local key, value = line:match("^([^=]+)=(.*)$")
      if current and key and value then
        current[trim(key)] = trim(value)
      end
    end
  end

  return entries
end

local function escape_json(value)
  value = value or ""
  value = value:gsub('\\', '\\\\')
  value = value:gsub('"', '\\"')
  value = value:gsub('\n', '\\n')
  return value
end

local function to_json(entries)
  local out = {"["}
  for i, entry in ipairs(entries) do
    local uri = escape_json(entry.uri or "")
    local title = escape_json(entry.title or "")
    local added = tonumber(entry.added_at or "0") or 0
    table.insert(out, string.format('  {"uri":"%s","title":"%s","added_at":%d}%s', uri, title, added, i < #entries and "," or ""))
  end
  table.insert(out, "]")
  return table.concat(out, "\n")
end

local function from_json(content)
  local entries = {}
  for uri, title, added in content:gmatch('{%s*"uri"%s*:%s*"(.-)"%s*,%s*"title"%s*:%s*"(.-)"%s*,%s*"added_at"%s*:%s*(%d+)%s*}') do
    table.insert(entries, {
      uri = uri:gsub('\\n', '\n'):gsub('\\"', '"'):gsub('\\\\', '\\'),
      title = title:gsub('\\n', '\n'):gsub('\\"', '"'):gsub('\\\\', '\\'),
      added_at = tonumber(added) or os.time()
    })
  end
  return entries
end

local function to_ini(entries)
  local out = {}
  for i, entry in ipairs(entries) do
    table.insert(out, string.format("[bookmark-%03d]", i - 1))
    table.insert(out, "uri=" .. (entry.uri or ""))
    table.insert(out, "title=" .. (entry.title or entry.uri or ""))
    table.insert(out, "added_at=" .. tostring(entry.added_at or os.time()))
    table.insert(out, "")
  end
  return table.concat(out, "\n")
end

local function usage()
  io.stderr:write("Usage:\n")
  io.stderr:write("  lua tools/bookmarks_tool.lua export <bookmarks.ini> <bookmarks.json>\n")
  io.stderr:write("  lua tools/bookmarks_tool.lua import <bookmarks.json> <bookmarks.ini>\n")
  os.exit(1)
end

if #arg ~= 3 then
  usage()
end

local mode = arg[1]
local input = arg[2]
local output = arg[3]

if mode == "export" then
  local ini, err = read_file(input)
  if not ini then
    io.stderr:write("Failed to read ini: " .. tostring(err) .. "\n")
    os.exit(2)
  end
  local parsed = parse_ini(ini)
  local json = to_json(parsed)
  local ok, write_err = write_file(output, json .. "\n")
  if not ok then
    io.stderr:write("Failed to write json: " .. tostring(write_err) .. "\n")
    os.exit(3)
  end
  io.stdout:write("Exported bookmarks to " .. output .. "\n")
elseif mode == "import" then
  local json, err = read_file(input)
  if not json then
    io.stderr:write("Failed to read json: " .. tostring(err) .. "\n")
    os.exit(2)
  end
  local parsed = from_json(json)
  local ini = to_ini(parsed)
  local ok, write_err = write_file(output, ini)
  if not ok then
    io.stderr:write("Failed to write ini: " .. tostring(write_err) .. "\n")
    os.exit(3)
  end
  io.stdout:write("Imported bookmarks to " .. output .. "\n")
else
  usage()
end
