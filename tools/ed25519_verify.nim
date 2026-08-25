import std/[os, osproc, strutils]

if paramCount() < 3:
  quit("Usage: ed25519_verify <public_key.pem> <message_file> <signature_file>", 1)

let pubKey = paramStr(1)
let message = paramStr(2)
let signature = paramStr(3)

if not fileExists(pubKey) or not fileExists(message) or not fileExists(signature):
  echo "verify=fail"
  echo "reason=missing_file"
  quit(2)

let cmd = "openssl pkeyutl -verify -pubin -inkey " &
  quoteShell(pubKey) & " -rawin -in " & quoteShell(message) &
  " -sigfile " & quoteShell(signature)
let (output, code) = execCmdEx(cmd)

if code == 0:
  echo "verify=ok"
  echo "reason=signature_valid"
  quit(0)

echo "verify=fail"
if output.strip().len > 0:
  echo "reason=" & output.strip().replace("\n", " ")
else:
  echo "reason=signature_invalid"
quit(3)
