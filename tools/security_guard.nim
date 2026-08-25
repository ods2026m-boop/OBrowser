import std/[os, strutils, sets, sequtils, uri]

if paramCount() < 3:
  quit("Usage: security_guard <url> <blocklist.txt> <whitelist.txt> [source_url]", 1)

let targetUri = paramStr(1).strip().toLowerAscii()
let blocklistPath = paramStr(2)
let whitelistPath = paramStr(3)
let sourceUri = if paramCount() >= 4: paramStr(4).strip().toLowerAscii() else: ""

proc extractHost(u: string): string =
  if u.startsWith("http://") or u.startsWith("https://"):
    let p = u.split("://", maxsplit = 1)
    if p.len == 2:
      return p[1].split('/')[0].split(':')[0].toLowerAscii()
  return ""

proc extractScheme(u: string): string =
  if not u.contains("://"):
    return ""
  let p = u.split("://", maxsplit = 1)
  if p.len == 2:
    return p[0].toLowerAscii()
  return ""

proc extractPath(u: string): string =
  if u.startsWith("http://") or u.startsWith("https://"):
    let p = u.split("://", maxsplit = 1)
    if p.len == 2:
      let slash = p[1].find('/')
      if slash >= 0:
        return p[1][slash .. ^1].toLowerAscii()
  return "/"

proc hasUserInfo(u: string): bool =
  if not (u.startsWith("http://") or u.startsWith("https://")):
    return false
  let p = u.split("://", maxsplit = 1)
  if p.len != 2:
    return false
  let hostPart = p[1].split('/')[0]
  return hostPart.contains("@")

proc hasControlChars(u: string): bool =
  for ch in u:
    if ord(ch) < 32:
      return true
  return false

proc hasEncodedControlChars(u: string): bool =
  let low = u.toLowerAscii()
  return low.contains("%00") or low.contains("%0a") or low.contains("%0d") or low.contains("%09")

proc looksLikePhishingHost(host: string): bool =
  if host.len == 0:
    return false
  for label in host.split('.'):
    if label.startsWith("xn--"):
      return true
  let labels = host.split('.')
  if labels.len >= 5:
    return true
  let risky = ["login", "verify", "secure", "account", "wallet", "banking", "update"]
  for token in risky:
    if host.contains(token):
      if host.contains("paypal") or host.contains("google") or host.contains("apple") or host.contains("microsoft"):
        return true
  return false

proc hasConfusableDelimiters(host: string): bool =
  if host.len == 0:
    return false
  if host.contains("--") or host.contains(".."):
    return true
  return host.contains("-login") or host.contains("-secure") or host.contains("-verify")

proc shannonLikeScore(host: string): float =
  if host.len == 0:
    return 0.0
  let chars = host.toSeq().deduplicate()
  return float(chars.len) / float(host.len)

proc riskyTld(host: string): bool =
  let bad = [".zip", ".mov", ".country", ".kim", ".cricket", ".gq"]
  for tld in bad:
    if host.endsWith(tld):
      return true
  return false

proc isNumericIpHost(host: string): bool =
  if host.len == 0:
    return false
  for part in host.split('.'):
    if part.len == 0:
      return false
    for ch in part:
      if ch < '0' or ch > '9':
        return false
  return host.split('.').len == 4

proc isPrivateOrLoopbackHost(host: string): bool =
  if host == "localhost":
    return true
  if not isNumericIpHost(host):
    return false
  let parts = host.split('.')
  if parts.len != 4:
    return false
  let a = parseInt(parts[0])
  let b = parseInt(parts[1])
  if a == 10 or a == 127:
    return true
  if a == 172 and b >= 16 and b <= 31:
    return true
  return a == 192 and b == 168

proc hasDangerousTraversal(u: string): bool =
  let low = u.toLowerAscii()
  return low.contains("../") or low.contains("..\\") or low.contains("%2e%2e") or low.contains("%252e%252e")

proc decodeUriSafe(u: string): string =
  try:
    return decodeUrl(u)
  except CatchableError:
    return u

# Decode percent-encoding repeatedly until the string stabilizes, so that
# multi-encoded payloads (e.g. %252e -> %2e -> ..) cannot evade the checks.
proc decodeUriSafeRepeated(u: string): string =
  var cur = u
  for i in 0 ..< 6:
    let d = decodeUriSafe(cur)
    if d == cur:
      break
    cur = d
  return cur

proc hostMatches(pattern: string, host: string): bool =
  let p = pattern.strip().toLowerAscii()
  let h = host.strip().toLowerAscii()
  if p.len == 0 or h.len == 0:
    return false
  if p.startsWith("*."):
    let suffix = p[2 .. ^1]
    if h == suffix:
      return true
    return h.endsWith("." & suffix)
  return h == p

var blocked = false
var reason = ""
var risk = "low"

if targetUri.len == 0:
  echo "decision=allow"
  echo "reason=empty"
  echo "risk=low"
  echo "policy_graph=entry->allow"
  quit(0)

if targetUri.startsWith("javascript:"):
  blocked = true
  reason = "javascript scheme blocked"
elif targetUri.startsWith("data:text/html"):
  blocked = true
  reason = "data html blocked"
elif targetUri.startsWith("file://"):
  blocked = false

let host = extractHost(targetUri)
let path = extractPath(targetUri)
let scheme = extractScheme(targetUri)
let decodedUri = decodeUriSafeRepeated(targetUri)
var trustedHost = false
var trustScopes = initHashSet[string]()

if host.len > 0 and fileExists(whitelistPath):
  for raw in readFile(whitelistPath).splitLines():
    let line = raw.strip().toLowerAscii()
    if line.len > 0 and not line.startsWith("#"):
      var parts = line.split('|')
      let domainRule = parts[0].strip()
      let scope = if parts.len >= 2 and parts[1].strip().len > 0: parts[1].strip() else: "all"
      if hostMatches(domainRule, host):
        trustedHost = true
        trustScopes.incl(scope)

proc trustedFor(scope: string): bool =
  return trustedHost and (trustScopes.contains("all") or trustScopes.contains(scope))

if not blocked and hasUserInfo(targetUri):
  blocked = true
  reason = "url userinfo blocked (phishing risk)"
  risk = "high"

if not blocked and not trustedFor("phishing") and looksLikePhishingHost(host):
  blocked = true
  reason = "host pattern flagged as phishing risk"
  risk = "high"

if not blocked and not trustedFor("phishing") and hasConfusableDelimiters(host):
  blocked = true
  reason = "confusable hostname delimiters blocked"
  risk = "medium"

if not blocked and not trustedFor("phishing") and host.len >= 18 and shannonLikeScore(host) > 0.72:
  blocked = true
  reason = "high-entropy hostname blocked"
  risk = "medium"

if not blocked and not trustedFor("phishing") and riskyTld(host):
  blocked = true
  reason = "risky tld blocked by policy"
  risk = "medium"

if not blocked and not trustedFor("phishing") and targetUri.startsWith("http://") and isNumericIpHost(host):
  if path.contains("login") or path.contains("signin") or path.contains("password") or path.contains("bank"):
    blocked = true
    reason = "sensitive http flow on numeric ip blocked"
    risk = "high"

# Simple mixed-content hardening: prevent insecure active resource jumps from secure pages
if not blocked and not trustedFor("mixed-content") and sourceUri.startsWith("https://") and targetUri.startsWith("http://"):
  if path.endsWith(".js") or path.endsWith(".mjs") or path.endsWith(".css") or path.endsWith(".wasm") or path.contains("/api/"):
    blocked = true
    reason = "mixed content active resource blocked"
    risk = "medium"

if not blocked and (targetUri.startsWith("http://") or (targetUri.startsWith("https://") and isNumericIpHost(host))):
  if path.endsWith(".exe") or path.endsWith(".msi") or path.endsWith(".dmg") or path.endsWith(".apk") or path.endsWith(".sh"):
    blocked = true
    reason = "insecure executable delivery blocked"
    risk = "high"

if not blocked and not trustedFor("sanitization") and (hasControlChars(targetUri) or hasEncodedControlChars(targetUri)):
  blocked = true
  reason = "encoded/control characters in url blocked"
  risk = "high"

if not blocked and not trustedFor("sanitization") and hasDangerousTraversal(decodedUri):
  blocked = true
  reason = "path traversal pattern in url blocked"
  risk = "high"

if not blocked and scheme == "http" and not trustedFor("localnet") and isPrivateOrLoopbackHost(host):
  blocked = true
  reason = "plaintext local network target blocked"
  risk = "high"

if not blocked and sourceUri.startsWith("https://") and scheme != "":
  if scheme != "https" and scheme != "wss" and scheme != "about" and scheme != "obrowser" and scheme != "data" and scheme != "blob":
    blocked = true
    reason = "cross-scheme downgrade blocked"
    risk = "medium"

if not blocked and host.len > 0 and fileExists(blocklistPath):
  var deny = initHashSet[string]()
  for raw in readFile(blocklistPath).splitLines():
    let line = raw.strip().toLowerAscii()
    if line.len > 0 and not line.startsWith("#"):
      deny.incl(line)
  for rule in deny:
    if hostMatches(rule, host):
      if not trustedFor("blocklist"):
        blocked = true
        reason = "domain in blocklist"
        risk = "medium"
      break

if blocked:
  echo "decision=block"
  echo "reason=" & reason
  echo "risk=" & risk
  echo "policy_graph=entry->scheme->whitelist_scope->risk_rules->blocklist->decision:block"
else:
  echo "decision=allow"
  echo "reason=ok"
  echo "risk=low"
  echo "policy_graph=entry->scheme->whitelist_scope->risk_rules->blocklist->decision:allow"

quit(0)
