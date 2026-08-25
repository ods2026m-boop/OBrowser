"""Tests for update_checker.lua and crash_uploader.lua tools.

Verifies the insecure update checker lacks HTTPS enforcement (documenting the
security gap that update_secure.lua fixes) and crash uploader works correctly.
"""

import os
import subprocess
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
TOOLS = ROOT / "tools"
UPDATE_CHECKER = TOOLS / "update_checker.lua"
CRASH_UPLOADER = TOOLS / "crash_uploader.lua"


@pytest.fixture
def tmp_dir():
    with tempfile.TemporaryDirectory() as d:
        yield Path(d)


class TestUpdateCheckerInsecure:
    """Document that the legacy update_checker lacks HTTPS enforcement.

    This is the insecure predecessor to update_secure.lua. It is kept for
    comparison but should NOT be used in production.
    """

    def test_legacy_checker_lacks_https_enforcement(self):
        """The legacy checker does NOT enforce HTTPS (documented weakness)."""
        content = UPDATE_CHECKER.read_text()
        # The legacy checker has no HTTPS validation
        assert "https://" not in content or "manifest_must_be_https" not in content, (
            "Legacy update_checker should not enforce HTTPS"
        )

    def test_secure_replacement_exists(self):
        """The secure replacement must exist."""
        secure = TOOLS / "update_secure.lua"
        assert secure.exists()
        content = secure.read_text()
        assert "manifest_must_be_https" in content


class TestCrashUploader:
    """Verify the crash uploader tool."""

    def test_requires_all_args(self, tmp_dir):
        """Crash uploader must require path, endpoint, and token."""
        result = subprocess.run(
            ["lua", str(CRASH_UPLOADER)],
            capture_output=True,
            text=True,
            cwd=str(ROOT),
            timeout=10,
        )
        assert result.returncode == 2

    def test_token_in_third_position(self, tmp_dir):
        """Verify token is passed as third argument (documented behavior)."""
        content = CRASH_UPLOADER.read_text()
        # Token is arg[3] in crash_uploader (different from sync_client)
        assert "arg[3]" in content

    def test_uses_binary_upload(self, tmp_dir):
        """Crash uploader should use --data-binary for log upload."""
        content = CRASH_UPLOADER.read_text()
        assert "--data-binary" in content
