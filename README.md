# OBrowser

A desktop web browser built with GTK and WebKitGTK.

OBrowser is written primarily in [Vala](https://vala-project.org/) for the
browser shell, with auxiliary tooling in [Lua](https://www.lua.org/) and
native security-critical sidecars in [Nim](https://nim-lang.org/). It targets
Linux desktop environments and uses the standard GLib directory layout
(`XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_CACHE_HOME`).

## Current status

OBrowser is under active development. The current implementation includes a
functional browser shell with tabbed browsing, bookmarks, history, session
management, downloads, password storage, permission handling, search engine
configuration, a userscript/userstyle extension system, a signed WebStore
catalog, a signed update system, a sync client, crash reporting, and a
security policy engine.

### Verified

The following are implemented and covered by automated tests:

- Full Vala build via `make`
- All three Nim sidecars compile and pass tests
- All nine Lua tool files pass syntax validation
- WebStore catalog signature verification (Ed25519)
- Secure update manifest verification (HTTPS + Ed25519)
- Sync client token handling (environment variable, not argv)
- Security guard URL policy enforcement
- WebStore path traversal protection
- Session dangerous-scheme validation
- 72 pytest regression checks pass (`make test`)

### Known limitations

- Only one search engine (Google) is configured by default
- The WebStore ships with two example extensions; the catalog is local, not fetched remotely
- Sync and crash upload require external endpoints configured by the user
- No automatic update download; the update system only checks availability and verifies signatures
- The project is not yet suitable for security-sensitive production use

## Features

Implemented features:

- **Tabbed browsing** — multiple tabs per window, with private window support
- **Bookmarks** — persistent bookmarks bar and dialog, import/export to JSON
- **History** — persistent history with search, automatic indexing via Nim sidecar
- **Downloads** — download manager with progress tracking and resume support
- **Session management** — automatic session restore on launch, periodic session snapshots
- **Password management** — saved passwords stored in the system keyring (libsecret)
- **Permissions** — prompt-based permission requests (location, notifications, media)
- **Search engines** — configurable search engine with omnibox integration
- **Extensions (WebStore)** — userscript and userstyle extensions from a signed catalog
- **Sync** — bookmarks, history, and settings sync to a user-configured endpoint
- **Update system** — signed update manifest verification with key rotation support
- **Security guard** — Nim-based URL policy engine for phishing, traversal, and mixed-content protection
- **Crash reporting** — GLib log capture and optional upload
- **Internal pages** — `obrowser://` internal pages including an about page and WebStore UI

## Architecture

```
OBrowser
├── Vala application
│   ├── BrowserWindow          Main window, tab container, UI chrome
│   ├── BrowserTab             Single tab with WebView and signals
│   ├── managers/
│   │   ├── BookmarkManager    Bookmarks persistence
│   │   ├── HistoryManager     History persistence and indexing
│   │   ├── DownloadManager    Download tracking and UI
│   │   ├── SessionManager     Session save/restore
│   │   ├── PasswordManager    Password storage via libsecret
│   │   ├── PermissionManager  WebKit permission prompts
│   │   ├── SearchEngineManager Search engine configuration
│   │   ├── SettingsManager    Persistent settings
│   │   ├── ExtensionManager   Userscript/userstyle extensions
│   │   ├── SyncManager        Sync orchestration
│   │   ├── UpdateManager      Update checking
│   │   ├── SecurityManager    Security policy orchestration
│   │   ├── CrashReporter      Log capture and upload
│   │   ├── ShortcutManager    Keyboard shortcuts
│   │   └── AppPaths           XDG directory management
│   ├── dialogs/               UI dialogs (preferences, history, bookmarks, etc.)
│   └── security/update/session components
│
├── Lua tools (tools/)
│   ├── update_secure.lua      Secure update manifest verifier
│   ├── update_checker.lua     Legacy update checker (deprecated)
│   ├── sync_client.lua        Sync upload client
│   ├── crash_uploader.lua     Crash log uploader
│   ├── webstore.lua           WebStore catalog lister/verifier
│   ├── webstore_update.lua    WebStore update checker
│   ├── bookmarks_tool.lua     Bookmark JSON/INI conversion
│   ├── history_report.lua     History reporting utility
│   └── session_inspector.lua  Session file inspector
│
└── Nim sidecars (tools/)
    ├── security_guard          URL policy enforcement engine
    ├── ed25519_verify         Ed25519 signature verification
    └── history_indexer        History domain indexing
```

### Component interactions

- The **Vala application** manages the GUI and browser state.
- The **SecurityManager** invokes the `security_guard` Nim sidecar as a subprocess to evaluate URLs.
- The **UpdateManager** invokes `update_secure.lua` to check for updates.
- The **SyncManager** invokes `sync_client.lua` to upload user data.
- The **CrashReporter** invokes `crash_uploader.lua` to upload logs.
- The **WebStoreDialog** invokes `webstore.lua` and `webstore_update.lua` for catalog operations.
- The **HistoryManager** uses the `history_indexer` Nim sidecar for domain statistics.
- The **PasswordManager** and **SettingsManager** use libsecret for credential storage.

## Security model

### Cryptographic verification

The following are verified cryptographically:

- **WebStore catalog signature** — `tools/webstore_catalog.json.sig` is verified against `tools/webstore_pubkey.pem` using Ed25519 via the `ed25519_verify` sidecar.
- **Update manifest signature** — Update manifests are verified against a pinned Ed25519 public key.
- **Package hash verification** — WebStore extension package contents are hashed with SHA-256 and compared against catalog-declared hashes.

### Policy checks

The following are enforced by policy, not cryptography:

- **URL filtering** — The `security_guard` Nim sidecar evaluates URLs against blocklists, whitelists, and heuristics for phishing, path traversal, mixed content, and dangerous schemes.
- **Dangerous session schemes** — `javascript:`, `data:text/html`, and `vbscript:` URIs are filtered from session restore.
- **HTTPS enforcement** — Update manifests and sync endpoints must use HTTPS.
- **WebStore path validation** — Package paths must be relative and free of traversal sequences.
- **Fail-closed updates** — The secure updater refuses to proceed if the manifest cannot be downloaded, the signature cannot be verified, or the pinned key is missing.

### Credential handling

- **Passwords** are stored in the system keyring via libsecret when available. A legacy file-based vault is migrated to the keyring on first use.
- **Sync tokens** are passed via the `OBROWSER_SYNC_TOKEN` environment variable, not on the command line, to avoid exposure via `ps` or `/proc/<pid>/cmdline`.
- **Crash tokens** are passed as arguments to the crash uploader; this is a known limitation.

### Key management

- The **production private key** (`webstore_privkey.pem`) must never be committed to this repository. It is listed in `.gitignore`.
- The **public key** (`webstore_pubkey.pem`) is shipped with the browser and used for signature verification.
- Catalog signing is performed via `make webstore-sign OBROWSER_WEBSTORE_PRIVKEY=<path>`.

### Limitations

- The security guard is a policy engine, not a sandbox. It can block known-bad patterns but does not guarantee safety against all malicious URLs.
- Update verification depends on the pinned public key distributed with the browser. Key rotation is supported but requires user-agent updates.
- No certificate pinning is implemented beyond the Ed25519 signature checks.

## Build requirements

### Required

| Dependency | Purpose | Version tested |
|------------|---------|----------------|
| GTK | GUI toolkit | 3.24.x |
| WebKitGTK | Web engine | 2.52.x |
| Vala | Compiler for browser source | 0.56.x |
| Nim | Compiler for sidecar tools | 2.2.x |
| Lua | Runtime for tooling | 5.5.x |
| libsecret | Password storage | 0.21.x |
| OpenSSL | Signature verification (via ed25519_verify) | (system) |
| pkg-config | Dependency detection | (system) |

### Development/CI only

| Dependency | Purpose | Version tested |
|------------|---------|----------------|
| Python | Test runner | 3.14.x |
| pytest | Test framework | 9.1.x |

Python and pytest are required only for running the test suite. They are not runtime dependencies of OBrowser.

### Installation (Arch Linux)

```bash
sudo pacman -S gtk3 webkit2gtk-4.1 vala nim lua libsecret openssl pkgconf
# Development only:
sudo pacman -S python pytest
```

Adjust package names for your distribution.

## Build instructions

### Normal build

```bash
make
```

This compiles the Nim sidecars and the Vala application, producing:
- `obrowser` — the main binary
- `build/history_indexer` — Nim sidecar
- `build/security_guard` — Nim sidecar
- `build/ed25519_verify` — Nim sidecar

### Nim sidecar build only

```bash
make nim-sidecar
```

### Run

```bash
make run
```

### Clean

```bash
make clean
```

### Install

```bash
make install
```

### Environment variables

| Variable | Purpose |
|----------|---------|
| `VALAC` | Vala compiler path (default: `valac`) |
| `NIM` | Nim compiler path (default: `nim`) |
| `VALA_C_WARN` | Suppress Vala C warnings (default: `-w`) |
| `PREFIX` | Installation prefix (default: `/usr/local`) |
| `OBROWSER_WEBSTORE_PRIVKEY` | Path to Ed25519 private key for catalog signing |

## Testing

### Run all tests

```bash
make test
```

This executes `python3 -m pytest tests/ -v`.

### Run specific test modules

```bash
python3 -m pytest tests/test_security_guard.py -v
python3 -m pytest tests/test_webstore.py -v
python3 -m pytest tests/test_update_secure.py -v
python3 -m pytest tests/test_sync_client.py -v
```

### Test structure

| File | Coverage |
|------|----------|
| `tests/test_security_guard.py` | URL policy enforcement (scheme, phishing, traversal, mixed content, blocklist) |
| `tests/test_lua_tools.py` | Lua syntax validation, private key protection |
| `tests/test_update_secure.py` | HTTPS enforcement, fail-closed, rollback detection |
| `tests/test_sync_client.py` | Token handling, HTTPS enforcement |
| `tests/test_webstore.py` | Path traversal, signature verification |
| `tests/test_webstore_update.py` | Update signature enforcement |
| `tests/test_session.py` | Session parsing, dangerous-scheme validation |
| `tests/test_nim_sidecars.py` | ed25519_verify, history_indexer |
| `tests/test_data_tools.py` | history_report, bookmarks_tool |
| `tests/test_other_tools.py` | Legacy update_checker, crash_uploader |

### Test design

- Tests use `subprocess` to invoke the actual Lua/Nim tools
- No network access is required
- Tests use temporary directories for all file operations
- No production keys or credentials are used in tests
- All tests are deterministic and isolated

## Development workflow

### 1. Clone

```bash
git clone <repository-url>
cd OBrowser
```

### 2. Install dependencies

See [Build requirements](#build-requirements) above.

### 3. Build

```bash
make
```

### 4. Run tests

```bash
make test
```

### 5. Make changes

Edit Vala source, Lua tools, or Nim sidecars as needed. Rebuild with `make`.

### 6. Add tests

For bug fixes, add a regression test in the appropriate `tests/test_*.py` file. For security fixes, add tests that verify the fix and that the vulnerability cannot be reintroduced.

### 7. Verify

```bash
make clean
make
make test
```

## Repository layout

```
OBrowser/
├── *.vala              Browser source files (Vala)
├── main.vala           Application entry point
├── Makefile            Build system
├── pytest.ini          Pytest configuration
├── CONTRIBUTING.md     Contribution guidelines
├── LICENSE             License file (see License section)
├── .gitignore          Git ignore rules
├── tests/              Python/pytest test suite
│   ├── conftest.py     Shared fixtures
│   └── test_*.py       Test modules
├── tools/              Lua and Nim tooling
│   ├── *.lua           Lua tools
│   ├── *.nim           Nim sidecar sources
│   ├── webstore_catalog.json       Signed WebStore catalog
│   ├── webstore_pubkey.pem         Ed25519 public key
│   ├── webstore_catalog.json.sig   Catalog signature
│   └── webstore_packages/          Extension packages
├── data/               Desktop file and icons
│   ├── obrowser.desktop
│   └── icons/
│       └── obrowser.svg
├── assets/             Project assets
├── build/              Compiled Nim sidecars (generated)
└── downloads/          Default download directory (created at runtime)
```

### Runtime directories

OBrowser uses the XDG base directory specification:

| Directory | Default location |
|-----------|------------------|
| Config | `~/.config/obrowser/` |
| Data | `~/.local/share/obrowser/` |
| Cache | `~/.cache/obrowser/` |

## WebStore / update trust model

### Trust anchor

The root of trust for both the WebStore catalog and the update system is an
Ed25519 key pair:

- **Public key** — `tools/webstore_pubkey.pem` is shipped with the browser
  and used to verify signatures at runtime.
- **Private key** — `tools/webstore_privkey.pem` is used to sign the catalog
  and must NOT be committed to this repository.

### Catalog signing

The catalog is signed with:

```bash
make webstore-sign OBROWSER_WEBSTORE_PRIVKEY=/path/to/private/key.pem
```

This produces `tools/webstore_catalog.json.sig`, which is verified by the
browser before trusting any catalog entry.

### Signature verification flow

1. The browser locates the catalog (`webstore_catalog.json`) and its signature
   (`webstore_catalog.json.sig`).
2. The `webstore.lua` tool invokes the `ed25519_verify` Nim sidecar with the
   public key, catalog, and signature.
3. If verification fails, the catalog is rejected and no extensions are loaded.

### Package integrity

Each catalog entry declares a `package_hash` (SHA-256). When verifying an
extension, the browser computes the hash of the package files and compares it
against the catalog declaration. A modified package will fail verification.

### Insecure fallback

The insecure `update_checker.lua` has been replaced by `update_secure.lua`,
which enforces HTTPS and signature verification. The insecure fallback must
not be restored. Any update mechanism that does not verify signatures or allows
HTTP manifests is a security regression.

## Security reporting

This project does not currently have a dedicated security contact or
vulnerability disclosure program.

If you discover a security vulnerability:

1. **Do not** file a public issue on the issue tracker.
2. **Do not** disclose the vulnerability publicly until it has been addressed.
3. Prepare a private report describing the vulnerability, its impact, and
   a suggested fix if possible.
4. Submit the report through the most private channel available for this
   repository (for example, a private communication to the repository
   maintainers via the platform on which the project is hosted).

The project does not currently offer a bug bounty or formal acknowledgment
program for security reports.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

This project does not currently have a license file. The `LICENSE` file
in the repository is absent, and no license terms have been finalized.

Until a license is added, contributors and users should assume that the
project is copyrighted by its authors and that no redistribution or
modification rights are granted by default.

If you are interested in contributing, check the repository for the most
current licensing information before submitting changes.
