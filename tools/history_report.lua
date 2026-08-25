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

local function parse_history_ini(content)
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

local function domain_of(uri)
  if not uri or uri == "" then
    return "(unknown)"
  end
  local host = uri:match("^[a-zA-Z]+://([^/%?#:]+)")
  if host then
    return host:lower()
  end
  if uri:match("^file://") then
    return "file://"
  end
  return "(unknown)"
end

local function to_number(value, fallback)
  local num = tonumber(value)
  if num == nil then
    return fallback
  end
  return num
end

local function format_time(ts)
  if ts <= 0 then
    return "unknown"
  end
  return os.date("%Y-%m-%d %H:%M:%S", ts)
end

local function iso_time(ts)
  return os.date("!%Y-%m-%dT%H:%M:%SZ", ts)
end

local function by_visits_desc(a, b)
  if a.visits == b.visits then
    return a.domain < b.domain
  end
  return a.visits > b.visits
end

local function by_recent_desc(a, b)
  return a.visited_at > b.visited_at
end

local function usage()
  io.stderr:write("Usage: lua tools/history_report.lua <history.ini> [top_n] [latest_n] [--json] [--output <file>]\n")
  os.exit(1)
end

if #arg < 1 then
  usage()
end

local history_path = arg[1]
local top_n = to_number(arg[2], 10)
local latest_n = to_number(arg[3], 10)
local as_json = false
local output_path = nil

local index = 4
while index <= #arg do
  if arg[index] == "--json" then
    as_json = true
    index = index + 1
  elseif arg[index] == "--output" then
    if index + 1 > #arg then
      usage()
    end
    output_path = arg[index + 1]
    index = index + 2
  else
    usage()
  end
end

if top_n < 1 then top_n = 10 end
if latest_n < 1 then latest_n = 10 end

local content, err = read_file(history_path)
if not content then
  io.stderr:write("Failed to read history file: " .. tostring(err) .. "\n")
  os.exit(2)
end

local parsed = parse_history_ini(content)
local normalized = {}
for _, entry in ipairs(parsed) do
  local uri = entry.uri or ""
  if uri ~= "" then
    table.insert(normalized, {
      uri = uri,
      title = entry.title or uri,
      visited_at = to_number(entry.visited_at, 0),
      visit_count = to_number(entry.visit_count, 1)
    })
  end
end

local domain_stats = {}
for _, item in ipairs(normalized) do
  local domain = domain_of(item.uri)
  if not domain_stats[domain] then
    domain_stats[domain] = { domain = domain, visits = 0, items = 0 }
  end
  domain_stats[domain].visits = domain_stats[domain].visits + item.visit_count
  domain_stats[domain].items = domain_stats[domain].items + 1
end

local domains = {}
for _, stats in pairs(domain_stats) do
  table.insert(domains, stats)
end

table.sort(domains, by_visits_desc)
table.sort(normalized, by_recent_desc)

if as_json then
  local tool_version = "1.1.0"
  local generated_at = iso_time(os.time())

  local function json_escape(value)
    value = value or ""
    value = value:gsub("\\", "\\\\")
    value = value:gsub("\"", "\\\"")
    value = value:gsub("\n", "\\n")
    return value
  end

  local domain_items = {}
  for i = 1, math.min(top_n, #domains) do
    local d = domains[i]
    table.insert(domain_items, string.format(
      "{\"rank\":%d,\"domain\":\"%s\",\"visits\":%d,\"entries\":%d}",
      i, json_escape(d.domain), d.visits, d.items
    ))
  end

  local latest_items = {}
  for i = 1, math.min(latest_n, #normalized) do
    local item = normalized[i]
    table.insert(latest_items, string.format(
      "{\"rank\":%d,\"title\":\"%s\",\"uri\":\"%s\",\"visit_count\":%d,\"visited_at\":%d,\"visited_at_text\":\"%s\"}",
      i,
      json_escape(item.title),
      json_escape(item.uri),
      item.visit_count,
      item.visited_at,
      json_escape(format_time(item.visited_at))
    ))
  end

  local out = {}
  table.insert(out, "{")
  table.insert(out, "\"schema_version\":\"1.0\",")
  table.insert(out, string.format("\"tool_version\":\"%s\",", json_escape(tool_version)))
  table.insert(out, string.format("\"generated_at\":\"%s\",", json_escape(generated_at)))
  table.insert(out, string.format("\"history_file\":\"%s\",", json_escape(history_path)))
  table.insert(out, string.format("\"entries\":%d,", #normalized))
  table.insert(out, "\"top_domains\":[" .. table.concat(domain_items, ",") .. "],")
  table.insert(out, "\"latest_entries\":[" .. table.concat(latest_items, ",") .. "]")
  table.insert(out, "}\n")
  local payload = table.concat(out)

  if output_path and output_path ~= "" then
    local file, err = io.open(output_path, "w")
    if not file then
      io.stderr:write("Failed to write output file: " .. tostring(err) .. "\n")
      os.exit(3)
    end
    file:write(payload)
    file:close()
  else
    io.write(payload)
  end
  os.exit(0)
end

print("History file: " .. history_path)
print("Entries     : " .. tostring(#normalized))

if #normalized == 0 then
  print("No history entries found.")
  os.exit(0)
end

print("")
print("Top domains (by total visits):")
for i = 1, math.min(top_n, #domains) do
  local d = domains[i]
  print(string.format(" %2d) %-30s visits=%d entries=%d", i, d.domain, d.visits, d.items))
end

print("")
print("Latest entries:")
for i = 1, math.min(latest_n, #normalized) do
  local item = normalized[i]
  print(string.format(" %2d) [%s] %s", i, format_time(item.visited_at), item.title))
  print(string.format("     uri=%s | visit_count=%d", item.uri, item.visit_count))
end
