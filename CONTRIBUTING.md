# Contributing to OBrowser

Thank you for your interest in contributing to OBrowser. This document
provides guidelines for contributing to the project.

## Before contributing

1. **Read the README** — Understand the project architecture, build system,
   and security model before making changes.
2. **Build successfully** — Ensure `make` completes without errors before
   submitting changes.
3. **Run tests** — Ensure `make test` passes before submitting changes.
4. **Understand the architecture** — Review the architecture section of the
   README to understand how Vala, Lua, and Nim components interact.
5. **Avoid unrelated changes** — Keep pull requests focused on a single
   issue or feature.

## Development environment

### Required tools

| Tool | Minimum version | Purpose |
|------|-----------------|---------|
| GTK | 3.24 | GUI toolkit |
| WebKitGTK | 4.1 | Web engine |
| Vala | 0.56 | Browser source compiler |
| Nim | 2.0 | Sidecar compiler |
| Lua | 5.4+ | Tool runtime |
| libsecret | 0.20 | Password storage |
| OpenSSL | (system) | Signature verification |
| pkg-config | (system) | Dependency detection |

### Development tools (CI only)

| Tool | Purpose |
|------|---------|
| Python 3 | Test runner |
| pytest | Test framework |

### Setup (Arch Linux)

```bash
sudo pacman -S gtk3 webkit2gtk-4.1 vala nim lua libsecret openssl pkgconf python pytest
```

## Build and test

### Build

```bash
make
```

This compiles the Nim sidecars and the Vala application.

### Build Nim sidecars only

```bash
make nim-sidecar
```

### Run tests

```bash
make test
```

### Run specific tests

```bash
python3 -m pytest tests/test_security_guard.py -v
python3 -m pytest tests/test_webstore.py -v
python3 -m pytest tests/ -k "sync" -v
```

### Clean build

```bash
make clean
make
```

### Full verification

```bash
make clean
make
make test
```

## Coding guidelines

### General principles

- **Correctness** — Code must work as intended and handle error cases.
- **Security** — Never weaken security checks to make code simpler.
- **Minimal changes** — Make the smallest change that solves the problem.
- **Predictable behavior** — Code should behave consistently and not surprise
  the reader.
- **Useful comments** — Comment why, not what. Explain non-obvious decisions.

### Vala

- Follow the existing code style in the project
- Use `var` for local variables when the type is obvious
- Handle `Error` exceptions with `try/catch` blocks
- Use `Shell.quote()` when passing arguments to subprocesses
- Use `Markup.escape_text()` when inserting user content into HTML
- Prefer signals over direct method calls for component communication
- Use the `OBrowserUtils` helper functions for common operations

### Lua

- Use `local` for all variables
- Use `string.format` for string interpolation
- Always `close()` files after opening them
- Use `Shell.quote()` equivalent (`sh_quote`) for shell arguments
- Handle `nil` returns from file operations
- Use `pcall` for operations that might fail
- Keep tools focused on a single responsibility

### Nim

- Follow the existing code style
- Use `let` for immutable bindings, `var` for mutable
- Handle exceptions with `try/except`
- Use `Option` types or result codes for operations that can fail
- Keep sidecars stateless where possible
- Document the expected input/output format

### Python tests

- Use descriptive test names that explain the expected behavior
- Use `pytest` fixtures for shared setup
- Use `tmp_path` or `tempfile` for file operations
- Use `subprocess.run` with `capture_output=True` for tool invocation
- Assert on specific expected values, not just return codes
- Group related tests in classes
- Use `@pytest.mark.skipif` for platform-specific tests

## Security-sensitive development

### Critical rules

1. **Never commit secrets** — Private keys, tokens, passwords, or other
   credentials must never be committed to the repository.
2. **Never commit the WebStore signing key** — The production private key
   (`webstore_privkey.pem`) must remain in a secure location outside the
   repository. Use environment variables or a secrets manager.
3. **Do not weaken signature verification** — Signature checks must not be
   bypassed, made optional, or replaced with weaker mechanisms.
4. **Do not add insecure update fallbacks** — The update system must not fall
   back to HTTP or skip signature verification on failure.
5. **Do not disable HTTPS checks** — Update manifests and sync endpoints must
   always require HTTPS.
6. **Do not bypass path validation** — WebStore package paths must always be
   validated for traversal attempts.
7. **Do not expose sync tokens** — Tokens must be passed via environment
   variables, not command-line arguments.
8. **Do not add shell interpolation of untrusted input** — Always use proper
   quoting when passing user-controlled data to shell commands.
9. **Add regression tests for security fixes** — Every security fix must
   include a test that verifies the fix and prevents regression.

### Security review

Changes to the following areas require extra scrutiny:

- `tools/security_guard.nim` — URL policy engine
- `tools/update_secure.lua` — Update verification
- `tools/sync_client.lua` — Sync client
- `tools/webstore.lua` — WebStore catalog handling
- `tools/ed25519_verify.nim` — Signature verification
- `SecurityManager.vala` — Security orchestration
- `UpdateManager.vala` — Update management
- `SyncManager.vala` — Sync management
- `PasswordManager.vala` — Password storage
- `SecretStore.vala` — Keyring access

## Testing contributions

### Requirements

- Add regression tests for bug fixes where practical
- Test security fixes explicitly with both positive and negative cases
- Keep tests deterministic — no randomness or time-dependent assertions
- Avoid network-dependent tests — mock or skip if network is required
- Use temporary directories for all file operations
- Ensure subprocess cleanup — use context managers or explicit cleanup
- Do not use real credentials or production keys in tests

### Test structure

Place tests in the appropriate `tests/test_*.py` file:

| File | Purpose |
|------|---------|
| `test_security_guard.py` | URL policy tests |
| `test_lua_tools.py` | Lua syntax and key protection |
| `test_update_secure.py` | Update verification |
| `test_sync_client.py` | Sync client behavior |
| `test_webstore.py` | WebStore security |
| `test_webstore_update.py` | WebStore update checks |
| `test_session.py` | Session handling |
| `test_nim_sidecars.py` | Nim sidecar functionality |
| `test_data_tools.py` | Data tool functionality |
| `test_other_tools.py` | Other tool tests |

### Example: Adding a security regression test

```python
def test_block_new_attack_vector(security_guard, blocklist_file, whitelist_file):
    """Verify the new attack vector is blocked."""
    rc, stdout, _ = run_tool([
        str(security_guard),
        "https://evil.example.com/new-attack",
        str(blocklist_file),
        str(whitelist_file),
    ])
    out = parse_keyval(stdout)
    assert out["decision"] == "block"
    assert "expected-reason" in out["reason"]
```

## Commit guidelines

### Commit message format

Use clear, descriptive commit messages:

```
<component>: <short summary>

<longer description if needed>
```

Examples:

```
security_guard: block data: URIs in URL policy

Add data: scheme to the blocked schemes list to prevent
data exfiltration via navigation.
```

```
webstore: reject packages with traversal paths

Package paths containing ".." or absolute paths are now
rejected during catalog parsing.
```

### Commit best practices

- One logical change per commit
- Reference issue numbers when applicable
- Do not mix unrelated changes in a single commit
- Ensure tests pass before committing

## Pull requests

### What to include

1. **Problem description** — What issue does this PR address?
2. **Solution** — What approach did you take?
3. **Tests** — What tests did you add or modify?
4. **Security implications** — Does this change affect security behavior?
5. **Screenshots** — Only when UI changes need visual verification
6. **Documentation** — Update README or this file if the change affects
   user-facing behavior

### PR checklist

- [ ] Build succeeds (`make`)
- [ ] Tests pass (`make test`)
- [ ] Security implications reviewed
- [ ] No secrets committed
- [ ] Documentation updated where needed
- [ ] Change is focused on a single issue

### Review process

- PRs will be reviewed for correctness, security, and style
- Security-sensitive changes may require additional review
- Feedback should be addressed with additional commits, not by force-pushing

## Scope discipline

Keep pull requests focused. Do not mix:

- **Unrelated refactors** with bug fixes
- **Large formatting changes** with functional changes
- **Dependency upgrades** with feature work
- **Multiple features** in a single PR

If you want to refactor code, submit a separate PR for the refactor and the
functional change.

## Security vulnerabilities

If you discover a security vulnerability:

1. **Do not** file a public issue
2. **Do not** disclose the vulnerability publicly
3. Prepare a private report with:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)
4. Submit through the most private channel available for this repository

The project does not currently have a formal vulnerability disclosure program
or dedicated security contact.

## License and contributions

This project does not currently have a license file. The `LICENSE` file
is absent from the repository.

Until a license is added:

- Contributors retain copyright to their contributions
- No explicit license is granted for redistribution or modification
- Contributors should inspect the repository for the most current licensing
  information before submitting changes

If you have questions about licensing, raise an issue or contact the
maintainers through the repository's communication channels.

## Documentation

Update documentation when your change affects:

- **README.md** — New features, changed build requirements, new commands
- **CONTRIBUTING.md** — New development workflows, changed guidelines
- **Code comments** — Non-obvious behavior, security decisions
- **Test documentation** — New test patterns, changed test infrastructure

## Final checklist

Before submitting your contribution:

- [ ] Build succeeds (`make`)
- [ ] Tests pass (`make test`)
- [ ] Security implications reviewed
- [ ] No secrets or private keys committed
- [ ] Documentation updated where needed
- [ ] Change is focused on a single issue
- [ ] Commit messages are clear and descriptive
- [ ] New tests added for bug fixes and security changes
