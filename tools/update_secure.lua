#!/usr/bin/env lua

local manifest_url = arg[1] or ""
local channel = arg[2] or "stable"
local current = arg[3] or "0.1.0"
local pinned_pubkey = arg[4] or ""
local next_pubkey = arg[5] or ""
local allow_rotation = (arg[6] or "false") == "true"
local rollback_state = arg[7] or ""

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

local function read_file(p)
  local f = io.open(p, "r")
  if not f then return nil end
  local c = f:read("*a")
  f:close()
  return c
end

local function write_file(p, c)
  local f = io.open(p, "w")
  if not f then return false end
  f:write(c)
  f:close()
  return true
end

if manifest_url == "" or not manifest_url:match("^https://") then
  print("update_available=false")
  print("reason=manifest_must_be_https")
  os.exit(0)
end

local tmpdir_handle = io.popen("mktemp -d 2>/dev/null")
local tmpdir = tmpdir_handle and tmpdir_handle:read("*l") or ""
if tmpdir_handle then tmpdir_handle:close() end
if tmpdir == "" then
  print("update_available=false")
  print("reason=secure_temp_unavailable")
  os.exit(0)
end

local tmp_manifest = tmpdir .. "/manifest.json"
local tmp_sig = tmpdir .. "/manifest.sig"

local function cleanup()
  os.execute("rm -rf " .. string.format("%q", tmpdir))
end

local curl_manifest = string.format("curl -fsSL %q -o %q", manifest_url, tmp_manifest)
local curl_sig = string.format("curl -fsSL %q -o %q", manifest_url .. ".sig", tmp_sig)
if os.execute(curl_manifest) ~= true and os.execute(curl_manifest) ~= 0 then
  cleanup()
  print("update_available=false")
  print("reason=manifest_download_failed")
  os.exit(0)
end
if os.execute(curl_sig) ~= true and os.execute(curl_sig) ~= 0 then
  cleanup()
  print("update_available=false")
  print("reason=signature_download_failed")
  os.exit(0)
end

if pinned_pubkey == "" or read_file(pinned_pubkey) == nil then
  print("update_available=false")
  print("reason=missing_pinned_pubkey")
  os.exit(0)
end

local verifier = "./build/ed25519_verify"
local rotated_to = ""
local verify_cmd = string.format("%s %q %q %q", verifier, pinned_pubkey, tmp_manifest, tmp_sig)
local r = os.execute(verify_cmd)
if r ~= true and r ~= 0 then
  if allow_rotation and next_pubkey ~= "" and read_file(next_pubkey) ~= nil then
    local verify_next = string.format("%s %q %q %q", verifier, next_pubkey, tmp_manifest, tmp_sig)
    local rr = os.execute(verify_next)
    if rr == true or rr == 0 then
      pinned_pubkey = next_pubkey
      rotated_to = next_pubkey
    else
      cleanup()
      print("update_available=false")
      print("reason=signature_verify_failed")
      os.exit(0)
    end
  else
    cleanup()
    print("update_available=false")
    print("reason=signature_verify_failed")
    os.exit(0)
  end
end

local raw = read_file(tmp_manifest) or ""
cleanup()
local latest = raw:match('"latest_version"%s*:%s*"(.-)"') or current
local notes = raw:match('"notes"%s*:%s*"(.-)"') or ""
local url = raw:match('"url"%s*:%s*"(.-)"') or ""
local manifest_channel = raw:match('"channel"%s*:%s*"(.-)"') or channel

if manifest_channel ~= channel then
  cleanup()
  print("update_available=false")
  print("reason=channel_mismatch")
  os.exit(0)
end

local last_seen = "0.0.0"
if rollback_state ~= "" then
  local prev = read_file(rollback_state)
  if prev then
    last_seen = prev:match("([%d%.]+)") or last_seen
  end
end

if semver_gt(last_seen, latest) then
  cleanup()
  print("update_available=false")
  print("reason=rollback_detected")
  os.exit(0)
end

if rollback_state ~= "" then
  write_file(rollback_state, latest .. "\n")
end

local avail = semver_gt(latest, current)
print("latest_version=" .. latest)
print("notes=" .. notes)
print("url=" .. url)
print("update_available=" .. (avail and "true" or "false"))
print("reason=ok")
if rotated_to ~= "" then
  print("rotated_pubkey=" .. rotated_to)
end
