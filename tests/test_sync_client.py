"""Tests for the sync_client.lua tool.

Verifies token handling (env var, not argv) and HTTPS enforcement.
"""

import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
TOOLS = ROOT / "tools"
SYNC_CLIENT = TOOLS / "sync_client.lua"


class TestSyncClientTokenHandling:
    """Verify the sync token is NOT passed via argv."""

    def test_token_not_in_argv(self):
        """The token must be read from environment, not command line."""
        content = SYNC_CLIENT.read_text()
        # Token must come from environment variable
        assert 'os.getenv("OBROWSER_SYNC_TOKEN")' in content or \
               "os.getenv('OBROWSER_SYNC_TOKEN')" in content, \
            "Sync token must be read from environment variable"
        # Token must NOT be in arg positions
        assert 'arg[2]' not in content or 'token' not in content.split('arg[2]')[0].split('\n')[-1], \
            "Token should not be passed as positional argument"

    def test_token_from_env_var(self, tmp_dir):
        """Verify token is read from OBROWSER_SYNC_TOKEN env var."""
        bookmarks = tmp_dir / "bookmarks.ini"
        history = tmp_dir / "history.ini"
        settings = tmp_dir / "settings.ini"
        bookmarks.write_text("[bookmark-000]\nuri=https://example.com\n")
        history.write_text("[history-000]\nuri=https://example.com\n")
        settings.write_text("[settings]\nhome_page=about:blank\n")

        env = os.environ.copy()
        env["OBROWSER_SYNC_TOKEN"] = "test-secret-token-12345"

        # Use a non-routable HTTPS endpoint so it fails on connection, not on validation
        result = subprocess.run(
            ["lua", str(SYNC_CLIENT),
             "https://127.0.0.1:19999/sync",
             str(bookmarks), str(history), str(settings)],
            capture_output=True,
            text=True,
            env=env,
            cwd=str(ROOT),
            timeout=10,
        )
        # Should fail on connection (not on missing token or HTTP rejection)
        assert result.returncode != 2, "Token should be accepted from env var"


class TestSyncClientHttpsEnforcement:
    """Verify HTTPS is enforced for sync endpoints."""

    def test_http_endpoint_rejected(self, tmp_dir):
        bookmarks = tmp_dir / "bookmarks.ini"
        history = tmp_dir / "history.ini"
        settings = tmp_dir / "settings.ini"
        bookmarks.write_text("")
        history.write_text("")
        settings.write_text("")

        env = os.environ.copy()
        env["OBROWSER_SYNC_TOKEN"] = "test-token"

        result = subprocess.run(
            ["lua", str(SYNC_CLIENT),
             "http://insecure.example.com/sync",
             str(bookmarks), str(history), str(settings)],
            capture_output=True,
            text=True,
            env=env,
            cwd=str(ROOT),
            timeout=10,
        )
        assert result.returncode == 2, "HTTP endpoint must be rejected"
        assert "HTTPS" in result.stderr or "https" in result.stderr

    def test_https_endpoint_accepted(self, tmp_dir):
        """HTTPS endpoint should pass validation (even if connection fails)."""
        bookmarks = tmp_dir / "bookmarks.ini"
        history = tmp_dir / "history.ini"
        settings = tmp_dir / "settings.ini"
        bookmarks.write_text("")
        history.write_text("")
        settings.write_text("")

        env = os.environ.copy()
        env["OBROWSER_SYNC_TOKEN"] = "test-token"

        result = subprocess.run(
            ["lua", str(SYNC_CLIENT),
             "https://127.0.0.1:19999/sync",
             str(bookmarks), str(history), str(settings)],
            capture_output=True,
            text=True,
            env=env,
            cwd=str(ROOT),
            timeout=10,
        )
        # Should NOT fail with code 2 (which means missing token or HTTP rejection)
        assert result.returncode != 2, "HTTPS endpoint should pass validation"
