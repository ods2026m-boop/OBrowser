#!/usr/bin/env lua

local command = arg[1]
local json_path = arg[2]

-- Minimal, correct recursive-descent JSON parser (no regex-based parsing).
local function parse_json(s)
  local pos = 1
  local function skip_ws()
    while pos <= #s do
      if s:sub(pos, pos):match("%s") then pos = pos + 1 else break end
    end
  end
  local parse_object, parse_array, parse_string, parse_number
  local function parse_value()
    skip_ws()
    local c = s:sub(pos, pos)
    if c == '{' then return parse_object() end
    if c == '[' then return parse_array() end
    if c == '"' then return parse_string() end
    if c == 't' then pos = pos + 4; return true end
    if c == 'f' then pos = pos + 5; return false end
    if c == 'n' then pos = pos + 4; return nil end
    return parse_number()
  end
  parse_object = function()
    local obj = {}
    pos = pos + 1
    skip_ws()
    if s:sub(pos, pos) == '}' then pos = pos + 1; return obj end
    while true do
      skip_ws()
      assert(s:sub(pos, pos) == '"')
      local key = parse_string()
      skip_ws()
      assert(s:sub(pos, pos) == ':'); pos = pos + 1
      obj[key] = parse_value()
      skip_ws()
      local ch = s:sub(pos, pos)
      if ch == ',' then pos = pos + 1
      elseif ch == '}' then pos = pos + 1; break
      else error("expected , or } in object") end
    end
    return obj
  end
  parse_array = function()
    local arr = {}
    pos = pos + 1
    skip_ws()
    if s:sub(pos, pos) == ']' then pos = pos + 1; return arr end
    while true do
      arr[#arr + 1] = parse_value()
      skip_ws()
      local ch = s:sub(pos, pos)
      if ch == ',' then pos = pos + 1
      elseif ch == ']' then pos = pos + 1; break
      else error("expected , or ] in array") end
    end
    return arr
  end
  parse_string = function()
    pos = pos + 1
    local out = {}
    while true do
      local c = s:sub(pos, pos)
      if c == '"' then pos = pos + 1; break end
      if c == '\\' then
        pos = pos + 1
        local e = s:sub(pos, pos)
        if e == '"' then out[#out + 1] = '"'
        elseif e == '\\' then out[#out + 1] = '\\'
        elseif e == '/' then out[#out + 1] = '/'
        elseif e == 'b' then out[#out + 1] = '\b'
        elseif e == 'f' then out[#out + 1] = '\f'
        elseif e == 'n' then out[#out + 1] = '\n'
        elseif e == 'r' then out[#out + 1] = '\r'
        elseif e == 't' then out[#out + 1] = '\t'
        elseif e == 'u' then
          local hex = s:sub(pos + 1, pos + 4)
          pos = pos + 4
          out[#out + 1] = utf8.char(tonumber(hex, 16))
        else error("bad escape") end
        pos = pos + 1
      else
        out[#out + 1] = c
        pos = pos + 1
      end
    end
    return table.concat(out)
  end
  parse_number = function()
    local start = pos
    while pos <= #s and s:sub(pos, pos):match("[%d%.%-%+eE]") do pos = pos + 1 end
    return tonumber(s:sub(start, pos - 1))
  end
  local ok, res = pcall(parse_value)
  if not ok then return nil end
  return res
end

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local c = f:read("*a")
  f:close()
  return c
end

local function file_exists(path)
  local f = io.open(path, "r")
  if not f then return false end
  f:close()
  return true
end

local function sh_quote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function find_first(pats)
  for _, p in ipairs(pats) do
    if file_exists(p) then return p end
  end
  return nil
end

-- Verify the catalog's Ed25519 signature using the independently-shipped
-- public key. The catalog content (including its package hashes) is only
-- trusted if this signature checks out; a modified catalog cannot redefine
-- its own trusted hashes.
local function catalog_is_trusted(catalog)
  local self_dir = (arg[0] and arg[0]:match("^(.*)/")) or "."
  local verifier = find_first({
    self_dir .. "/../build/ed25519_verify",
    self_dir .. "/../lib/obrowser/build/ed25519_verify",
    self_dir .. "/../share/obrowser/build/ed25519_verify",
    "build/ed25519_verify",
    "ed25519_verify"
  })
  local pubkey = find_first({
    self_dir .. "/webstore_pubkey.pem",
    self_dir .. "/../share/obrowser/tools/webstore_pubkey.pem",
    "tools/webstore_pubkey.pem"
  })
  local sig = catalog .. ".sig"
  if not verifier or not pubkey or not file_exists(sig) then
    return false
  end
  local cmd = string.format("%s %s %s %s", verifier, sh_quote(pubkey), sh_quote(catalog), sh_quote(sig))
  local ok = os.execute(cmd)
  return ok == true or ok == 0
end

local function is_safe_package_relative_path (rel)
  if rel == nil then return true end
  local r = tostring (rel)
  -- Reject absolute paths and any traversal that could escape the package dir.
  if r:match ("^/") then return false end
  if r:match ("%.%.") then return false end
  return true
end

local function parse_entries(raw)
  local entries = {}
  local data = parse_json(raw)
  if not data or type(data) ~= "table" or type(data.items) ~= "table" then
    return entries
  end
  for _, item in ipairs(data.items) do
    if type(item) == "table" then
      local id = item.id or ""
      local name = item.name or ""
      local script = item.script or ""
      local style = item.style or ""
      if id ~= "" and name ~= "" then
        if not is_safe_package_relative_path (script) or not is_safe_package_relative_path (style) then
          io.stderr:write ("Refusing catalog entry '" .. id .. "': unsafe package path.\n")
        else
          table.insert(entries, {
            id = id,
            name = name,
            description = item.description or "",
            script = script,
            style = style,
            category = item.category or "general",
            version = item.version or "1.0.0",
            manifest = item.manifest or "",
            package_hash = item.package_hash or ""
          })
        end
      end
    end
  end
  return entries
end

local function sha256_of_paths(script_path, style_path)
  local cmd
  if style_path ~= "" then
    cmd = "cat " .. sh_quote(script_path) .. " " .. sh_quote(style_path) .. " | sha256sum"
  else
    cmd = "cat " .. sh_quote(script_path) .. " | sha256sum"
  end
  local p = io.popen(cmd)
  if not p then return "" end
  local out = p:read("*l") or ""
  p:close()
  return (out:match("^(%x+)") or ""):gsub("%s+$", "")
end

if command ~= "list" and command ~= "verify" then
  io.stderr:write("Usage:\n  webstore.lua list <catalog.json>\n  webstore.lua verify <catalog.json> <id>\n")
  os.exit(1)
end

if not catalog_is_trusted(json_path or "") then
  io.stderr:write("Refusing to use catalog: signature verification failed or trust root unavailable.\n")
  os.exit(5)
end

local raw = read_file(json_path or "")
if not raw then
  io.stderr:write("Catalog file not found: " .. tostring(json_path) .. "\n")
  os.exit(2)
end

local base = json_path:gsub("[^/]+$", "")
local entries = parse_entries(raw)

if command == "list" then
  for _, e in ipairs(entries) do
    local script_path = e.script ~= "" and (base .. e.script) or ""
    local style_path = e.style ~= "" and (base .. e.style) or ""
    print(table.concat({e.id, e.name, e.description, e.category, e.version, e.package_hash, e.manifest, script_path, style_path}, "\t"))
  end
  os.exit(0)
end

local target_id = arg[3] or ""
for _, e in ipairs(entries) do
  if e.id == target_id then
    local script_path = e.script ~= "" and (base .. e.script) or ""
    local style_path = e.style ~= "" and (base .. e.style) or ""
    local got = sha256_of_paths(script_path, style_path)
    if got ~= "" and e.package_hash ~= "" and got == e.package_hash then
      print("ok\t" .. got)
      os.exit(0)
    end
    print("fail\t" .. got)
    os.exit(3)
  end
end

io.stderr:write("Entry not found: " .. target_id .. "\n")
os.exit(4)
