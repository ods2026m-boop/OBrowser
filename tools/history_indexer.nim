import std/[strutils, tables, os, algorithm]

if paramCount() < 2:
  quit("Usage: history_indexer <history.ini> <out.index>", 1)

let historyPath = paramStr(1)
let outPath = paramStr(2)

if not fileExists(historyPath):
  writeFile(outPath, "")
  quit(0)

let content = readFile(historyPath)
var domains = initCountTable[string]()
var currentUri = ""

for rawLine in content.splitLines():
  let line = rawLine.strip()
  if line.startsWith("uri="):
    currentUri = line[4 .. ^1]
    if currentUri.len > 0:
      var domain = ""
      if currentUri.startsWith("http://") or currentUri.startsWith("https://"):
        let noScheme = currentUri.split("://", maxsplit = 1)
        if noScheme.len == 2:
          domain = noScheme[1].split('/')[0]
      elif currentUri.startsWith("file://"):
        domain = "file://"
      else:
        domain = "unknown"
      if domain.len > 0:
        domains.inc(domain)

var rows: seq[(string, int)] = @[]
for k, v in domains.pairs:
  rows.add((k, v))
rows.sort(proc(a, b: (string, int)): int = cmp(b[1], a[1]))

var output = "# domain\tvisits\n"
for row in rows:
  output.add(row[0] & "\t" & $row[1] & "\n")

writeFile(outPath, output)
quit(0)
