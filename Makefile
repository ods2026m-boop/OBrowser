VALAC ?= valac
PKGS = --pkg gtk+-3.0 --pkg webkit2gtk-4.1 --pkg libsecret-1
TARGET = obrowser
SRC = $(sort $(wildcard *.vala))
VALA_C_WARN ?= -w
NIM ?= nim
PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
DATADIR ?= $(PREFIX)/share/applications
ICONDIR ?= $(PREFIX)/share/icons/hicolor/scalable/apps
LIBDIR ?= $(PREFIX)/lib/obrowser
SHAREDIR ?= $(PREFIX)/share/obrowser
IN_BOOKMARKS ?= $(HOME)/.local/share/obrowser/bookmarks.ini
IN_HISTORY ?= $(HOME)/.local/share/obrowser/history.ini
IN_SETTINGS ?= $(HOME)/.config/obrowser/settings.ini
LOG ?= $(HOME)/.cache/obrowser/crash.log

all: nim-sidecar $(TARGET)

$(TARGET): $(SRC)
	$(VALAC) $(PKGS) -X $(VALA_C_WARN) -o $(TARGET) $(SRC)

nim-sidecar:
	mkdir -p build
	$(NIM) c -d:release --out:build/history_indexer tools/history_indexer.nim
	$(NIM) c -d:release --out:build/security_guard tools/security_guard.nim
	$(NIM) c -d:release --out:build/ed25519_verify tools/ed25519_verify.nim

run: $(TARGET)
	./$(TARGET)

nim-sidecar:
	mkdir -p build
	$(NIM) c -d:release --out:build/history_indexer tools/history_indexer.nim
	$(NIM) c -d:release --out:build/security_guard tools/security_guard.nim
	$(NIM) c -d:release --out:build/ed25519_verify tools/ed25519_verify.nim

nim-sidecar-run: nim-sidecar
	build/history_indexer "$(HOME)/.local/share/obrowser/history.ini" "$(HOME)/.cache/obrowser/history.index"

tools-help:
	@echo "Lua tools:"
	@echo "  make bookmarks-export IN=<bookmarks.ini> OUT=<bookmarks.json>"
	@echo "  make bookmarks-import IN=<bookmarks.json> OUT=<bookmarks.ini>"
	@echo "  make session-inspect IN=<session.ini>"
	@echo "  make history-report IN=<history.ini> [TOP=10] [LATEST=10]"
	@echo "  make history-report-json IN=<history.ini> [TOP=10] [LATEST=10] [OUT=/tmp/report.json]"
	@echo "  make update-check MANIFEST=<url> [CHANNEL=stable] [CURRENT=0.1.0]"
	@echo "  make sync-run ENDPOINT=<url> TOKEN=<token>"
	@echo "  make crash-upload ENDPOINT=<url> TOKEN=<token> [LOG=~/.cache/obrowser/crash.log]"
	@echo "  make webstore-list"
	@echo "  make webstore-updates IN_EXT=<extensions.ini>"
	@echo "  make update-check-secure MANIFEST=<url> CHANNEL=<stable|beta|dev> CURRENT=<ver> PUBKEY=<pem>"
	@echo "  make nim-sidecar"
	@echo "  make nim-sidecar-run"
	@echo "  build/security_guard <url> <blocklist> <whitelist> [source_url]"

bookmarks-export:
	lua tools/bookmarks_tool.lua export "$(IN)" "$(OUT)"

bookmarks-import:
	lua tools/bookmarks_tool.lua import "$(IN)" "$(OUT)"

session-inspect:
	lua tools/session_inspector.lua "$(IN)"

history-report:
	lua tools/history_report.lua "$(IN)" "$(TOP)" "$(LATEST)"

history-report-json:
	lua tools/history_report.lua "$(IN)" "$(TOP)" "$(LATEST)" --json $(if $(OUT),--output "$(OUT)",)

# Private key for signing the WebStore catalog. MUST NOT live in this repo.
# Provide it via this environment variable (e.g. from a CI secrets manager).
OBROWSER_WEBSTORE_PRIVKEY ?= tools/webstore_privkey.pem

update-check:
	lua tools/update_checker.lua "$(MANIFEST)" "$(CHANNEL)" "$(CURRENT)"

sync-run:
	lua tools/sync_client.lua "$(ENDPOINT)" "$(TOKEN)" "$(IN_BOOKMARKS)" "$(IN_HISTORY)" "$(IN_SETTINGS)"

crash-upload:
	lua tools/crash_uploader.lua "$(LOG)" "$(ENDPOINT)" "$(TOKEN)"

webstore-list:
	lua tools/webstore.lua list tools/webstore_catalog.json

webstore-updates:
	lua tools/webstore_update.lua check tools/webstore_catalog.json "$(IN_EXT)"

update-check-secure:
	lua tools/update_secure.lua "$(MANIFEST)" "$(CHANNEL)" "$(CURRENT)" "$(PUBKEY)" "$(HOME)/.cache/obrowser/update_last_seen.txt"

install: nim-sidecar $(TARGET)
	install -d $(DESTDIR)$(BINDIR) $(DESTDIR)$(DATADIR) $(DESTDIR)$(ICONDIR) $(DESTDIR)$(LIBDIR)/build $(DESTDIR)$(SHAREDIR)/tools
	install -m 0755 $(TARGET) $(DESTDIR)$(BINDIR)/$(TARGET)
	install -m 0644 data/obrowser.desktop $(DESTDIR)$(DATADIR)/obrowser.desktop
	install -m 0644 data/icons/obrowser.svg $(DESTDIR)$(ICONDIR)/obrowser.svg
	install -m 0755 build/history_indexer build/security_guard build/ed25519_verify $(DESTDIR)$(LIBDIR)/build/
	install -m 0644 tools/webstore.lua tools/webstore_update.lua tools/sync_client.lua tools/crash_uploader.lua tools/update_secure.lua tools/update_checker.lua tools/bookmarks_tool.lua tools/history_report.lua tools/session_inspector.lua $(DESTDIR)$(SHAREDIR)/tools/
	install -m 0644 tools/webstore_catalog.json tools/webstore_pubkey.pem tools/webstore_catalog.json.sig $(DESTDIR)$(SHAREDIR)/tools/ 2>/dev/null || true

webstore-sign:
	@if [ ! -f "$(OBROWSER_WEBSTORE_PRIVKEY)" ]; then \
		echo "ERROR: WebStore signing key not found at $(OBROWSER_WEBSTORE_PRIVKEY)." >&2; \
		echo "Set OBROWSER_WEBSTORE_PRIVKEY to the path of the Ed25519 private key." >&2; \
		echo "The key must NOT be stored in this repository." >&2; \
		exit 1; \
	fi
	openssl pkeyutl -sign -inkey "$(OBROWSER_WEBSTORE_PRIVKEY)" -rawin -in tools/webstore_catalog.json -out tools/webstore_catalog.json.sig
	@echo "Re-signed tools/webstore_catalog.json -> tools/webstore_catalog.json.sig"

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/$(TARGET)
	rm -f $(DESTDIR)$(DATADIR)/obrowser.desktop
	rm -f $(DESTDIR)$(ICONDIR)/obrowser.svg
	rm -rf $(DESTDIR)$(LIBDIR)
	rm -rf $(DESTDIR)$(SHAREDIR)

test:
	python3 -m pytest tests/ -v

clean:
	rm -f $(TARGET) *.c
	rm -rf build
