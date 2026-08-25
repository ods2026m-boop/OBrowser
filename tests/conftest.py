"""Shared fixtures for OBrowser security regression tests."""

import os
import subprocess
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
TOOLS = ROOT / "tools"
BUILD = ROOT / "build"


@pytest.fixture
def tools_dir():
    return TOOLS


@pytest.fixture
def build_dir():
    return BUILD


@pytest.fixture
def security_guard():
    path = BUILD / "security_guard"
    if not path.exists():
        pytest.skip("security_guard not built; run `make nim-sidecar`")
    return path


@pytest.fixture
def ed25519_verify():
    path = BUILD / "ed25519_verify"
    if not path.exists():
        pytest.skip("ed25519_verify not built; run `make nim-sidecar`")
    return path


@pytest.fixture
def history_indexer():
    path = BUILD / "history_indexer"
    if not path.exists():
        pytest.skip("history_indexer not built; run `make nim-sidecar`")
    return path


@pytest.fixture
def tmp_dir():
    with tempfile.TemporaryDirectory() as d:
        yield Path(d)


@pytest.fixture
def blocklist_file(tmp_dir):
    p = tmp_dir / "blocklist.txt"
    p.write_text("# test blocklist\nmalware.example\ntracker.bad\n")
    return p


@pytest.fixture
def whitelist_file(tmp_dir):
    p = tmp_dir / "whitelist.txt"
    p.write_text("# test whitelist\ntrustedsite.com|all\napi.example.com|phishing\n")
    return p


def run_tool(cmd, env=None, cwd=None):
    """Run a tool and return (returncode, stdout, stderr)."""
    final_env = os.environ.copy()
    if env:
        final_env.update(env)
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        env=final_env,
        cwd=cwd or str(ROOT),
        timeout=30,
    )
    return result.returncode, result.stdout, result.stderr


def parse_keyval(output):
    """Parse key=value output lines into a dict."""
    out = {}
    for line in output.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    return out
