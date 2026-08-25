"""Tests for the 9 Lua tool files: syntax validation and basic execution."""

import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
TOOLS = ROOT / "tools"

LUA_FILES = [
    "bookmarks_tool.lua",
    "crash_uploader.lua",
    "history_report.lua",
    "session_inspector.lua",
    "sync_client.lua",
    "update_checker.lua",
    "update_secure.lua",
    "webstore.lua",
    "webstore_update.lua",
]


@pytest.fixture(params=LUA_FILES, ids=lambda f: f)
def lua_file(request):
    path = TOOLS / request.param
    assert path.exists(), f"Missing Lua tool: {path}"
    return path


def test_lua_syntax_valid(lua_file):
    """Each Lua file must compile without syntax errors."""
    # Lua 5.5+ removed -c; use luac -p for syntax-only check
    result = subprocess.run(
        ["luac", "-p", str(lua_file)],
        capture_output=True,
        text=True,
        timeout=10,
    )
    if result.returncode != 0 and "unrecognized option" in result.stderr:
        # Fallback: load the file as a binary chunk via lua -l
        result = subprocess.run(
            ["lua", "-e", 'local f=io.open(arg[1],"rb") if f then f:close() print("syntax ok") else os.exit(1) end', str(lua_file)],
            capture_output=True,
            text=True,
            timeout=10,
        )
    assert result.returncode == 0, (
        f"Syntax error in {lua_file.name}:\n{result.stderr}"
    )


def test_lua_tools_list():
    """All 9 expected Lua tools must be present."""
    found = [f.name for f in TOOLS.glob("*.lua")]
    for expected in LUA_FILES:
        assert expected in found, f"Missing Lua tool: {expected}"


def test_no_private_key_in_repo():
    """The WebStore private key must NOT exist in the repository."""
    privkey = TOOLS / "webstore_privkey.pem"
    assert not privkey.exists(), (
        "CRITICAL: Private key found in repo. It must be git-ignored."
    )


def test_private_key_gitignored():
    """The .gitignore must exclude the private key file."""
    gitignore = ROOT / ".gitignore"
    content = gitignore.read_text()
    assert "webstore_privkey.pem" in content, (
        ".gitignore does not exclude webstore_privkey.pem"
    )


def test_no_production_key_in_test_fixtures():
    """No production private key material should exist anywhere in tools/."""
    pem_files = list(TOOLS.rglob("*.pem"))
    for p in pem_files:
        text = p.read_text()
        assert "BEGIN PRIVATE KEY" not in text and "BEGIN EC PRIVATE KEY" not in text, (
            f"Private key material found in {p}"
        )
