#!/usr/bin/env lua

local cmd = arg[1]
local catalog_path = arg[2]
local extensions_ini = arg[3]

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

local function parse_catalog(raw)
  local items = {}
  for block in raw:gmatch("{(.-)}") do
    local id = block:match('"id"%s*:%s*"(.-)"') or ""
    local version = block:match('"version"%s*:%s*"(.-)"') or ""
    if id ~= "" and version ~= "" then
      items[id] = version
    end
  end
  return items
end

local function parse_extensions(raw)
  local found = {}
  local current_group = nil
  for line in raw:gmatch("[^\r\n]+") do
    local group = line:match("^%[(.-)%]$")
    if group then
      current_group = group
      found[current_group] = found[current_group] or {}
    else
      local k, v = line:match("^([%w_]+)%s*=%s*(.-)%s*$")
      if current_group and k and v then
        found[current_group][k] = v
      end
    end
  end
  return found
end

local function semver_gt(a, b)
  local function split(v)
    local t = {}
    for p in (v or "0"):gmatch("(%d+)") do
      table.insert(t, tonumber(p) or 0)
    end
    return t
  end
  local aa, bb = split(a), split(b)
  local n = math.max(#aa, #bb)
  for i = 1, n do
    local x, y = aa[i] or 0, bb[i] or 0
    if x > y then return true end
    if x < y then return false end
  end
  return false
end

if cmd ~= "check" then
  io.stderr:write("Usage: webstore_update.lua check <catalog.json> <extensions.ini>\n")
  os.exit(1)
end

local cat_raw = read_file(catalog_path or "")
local ext_raw = read_file(extensions_ini or "")
if not cat_raw or not ext_raw then
  os.exit(0)
end

if not catalog_is_trusted(catalog_path) then
  io.stderr:write("Refusing to use catalog: signature verification failed or trust root unavailable.\n")
  os.exit(5)
end

local latest = parse_catalog(cat_raw)
local installed = parse_extensions(ext_raw)

for _, data in pairs(installed) do
  local sid = data["store_id"] or ""
  local cur = data["version"] or "0.0.0"
  if sid ~= "" and latest[sid] and semver_gt(latest[sid], cur) then
    print(sid .. "\t" .. cur .. "\t" .. latest[sid])
  end
end
