"""Tests for the webstore_update.lua tool.

Verifies update checking with signature verification.
"""

import json
import subprocess
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
TOOLS = ROOT / "tools"
WEBSTORE_UPDATE = TOOLS / "webstore_update.lua"


@pytest.fixture
def tmp_dir():
    with tempfile.TemporaryDirectory() as d:
        yield Path(d)


class TestWebstoreUpdateSignature:
    """Verify webstore_update checks catalog signature."""

    def test_reject_unsigned_catalog_update(self, tmp_dir):
        """Update check on unsigned catalog must fail."""
        catalog = {
            "version": 1,
            "items": [{
                "id": "test-ext",
                "name": "Test",
                "version": "2.0.0",
            }]
        }
        cat_path = tmp_dir / "catalog.json"
        cat_path.write_text(json.dumps(catalog))

        ext_path = tmp_dir / "extensions.ini"
        ext_path.write_text("[test-ext]\nstore_id=test-ext\nversion=1.0.0\n")

        result = subprocess.run(
            ["lua", str(WEBSTORE_UPDATE), "check", str(cat_path), str(ext_path)],
            capture_output=True,
            text=True,
            cwd=str(ROOT),
            timeout=10,
        )
        assert result.returncode == 5, "Unsigned catalog must be rejected for updates"
        assert "signature" in result.stderr.lower() or "trust" in result.stderr.lower()

    def test_update_detection_with_trusted_catalog(self, tmp_dir):
        """Detects available updates when catalog is trusted."""
        cat_path = TOOLS / "webstore_catalog.json"
        sig_path = TOOLS / "webstore_catalog.json.sig"

        if not cat_path.exists() or not sig_path.exists():
            pytest.skip("Production catalog not available")

        # Create extensions.ini with an older version
        ext_path = tmp_dir / "extensions.ini"
        ext_path.write_text(
            "[reader-mode]\nstore_id=reader-mode\nversion=0.5.0\n"
            "[clean-video]\nstore_id=clean-video\nversion=0.9.0\n"
        )

        result = subprocess.run(
            ["lua", str(WEBSTORE_UPDATE), "check", str(cat_path), str(ext_path)],
            capture_output=True,
            text=True,
            cwd=str(ROOT),
            timeout=10,
        )
        assert result.returncode == 0
        # Both extensions should show updates available
        assert "reader-mode" in result.stdout
        assert "clean-video" in result.stdout
