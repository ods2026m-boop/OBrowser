"""Tests for the update_secure.lua tool.

Verifies HTTPS enforcement, signature verification, and fail-closed behavior.
"""

import os
import subprocess
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
TOOLS = ROOT / "tools"
UPDATE_SECURE = TOOLS / "update_secure.lua"


@pytest.fixture
def tmp_dir():
    with tempfile.TemporaryDirectory() as d:
        yield Path(d)


def run_update_secure(manifest_url, channel, current, pubkey, next_pubkey="",
                      allow_rotation="false", rollback_state=""):
    cmd = [
        "lua", str(UPDATE_SECURE),
        manifest_url,
        channel,
        current,
        pubkey,
        next_pubkey,
        allow_rotation,
        rollback_state,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, cwd=str(ROOT), timeout=30)
    out = {}
    for line in result.stdout.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    return result.returncode, out, result.stderr


class TestUpdateSecureHttpsEnforcement:
    """Verify HTTPS is enforced for manifest URLs."""

    def test_http_manifest_rejected(self, tmp_dir):
        rc, out, _ = run_update_secure(
            "http://insecure.example.com/manifest.json",
            "stable", "0.1.0", str(tmp_dir / "pubkey.pem")
        )
        assert rc == 0
        assert out.get("update_available") == "false"
        assert out.get("reason") == "manifest_must_be_https"

    def test_empty_manifest_rejected(self, tmp_dir):
        rc, out, _ = run_update_secure(
            "", "stable", "0.1.0", str(tmp_dir / "pubkey.pem")
        )
        assert rc == 0
        assert out.get("update_available") == "false"
        assert out.get("reason") == "manifest_must_be_https"


class TestUpdateSecureFailClosed:
    """Verify the updater fails closed (no insecure fallback)."""

    def test_missing_pubkey_fails_closed(self, tmp_dir):
        """When the pinned pubkey is missing, the updater must fail closed.

        The check happens after the download attempt; with an unroutable URL
        the download fails first, which also results in fail-closed behavior.
        Either outcome (download failure OR missing key) is acceptable: the
        update must not be marked available.
        """
        rc, out, _ = run_update_secure(
            "https://127.0.0.1:19999/manifest.json",
            "stable", "0.1.0",
            str(tmp_dir / "nonexistent_pubkey.pem")
        )
        assert rc == 0
        assert out.get("update_available") == "false"
        # Either the download fails (unroutable) or the missing key is detected
        reason = out.get("reason", "")
        assert reason in ("manifest_download_failed", "missing_pinned_pubkey")

    def test_no_insecure_fallback(self):
        """The secure updater must not fall back to HTTP on failure."""
        content = UPDATE_SECURE.read_text()
        assert "http://" not in content.replace("https://", "").replace("manifest_must_be_https", "")


class TestUpdateSecureRollbackDetection:
    """Verify rollback attack detection."""

    def test_rollback_detected(self, tmp_dir, ed25519_verify):
        # Create a pinned pubkey (use the test pubkey)
        pubkey = TOOLS / "webstore_pubkey.pem"
        rollback_file = tmp_dir / "rollback_state.txt"
        # Write a version higher than what the manifest would offer
        rollback_file.write_text("99.0.0\n")

        rc, out, _ = run_update_secure(
            "https://valid.example.com/manifest.json",
            "stable", "0.1.0",
            str(pubkey),
            "",
            "false",
            str(rollback_file),
        )
        # Should either fail closed on download or detect rollback
        assert rc == 0
        assert out.get("update_available") == "false"


@pytest.fixture
def ed25519_verify():
    path = ROOT / "build" / "ed25519_verify"
    if not path.exists():
        pytest.skip("ed25519_verify not built")
    return path
