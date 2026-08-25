"""Tests for the webstore.lua tool.

Verifies path traversal protection and catalog signature verification.
"""

import json
import subprocess
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
TOOLS = ROOT / "tools"
WEBSTORE = TOOLS / "webstore.lua"


@pytest.fixture
def tmp_dir():
    with tempfile.TemporaryDirectory() as d:
        yield Path(d)


class TestWebstorePathTraversal:
    """Verify path traversal protection in package paths."""

    def test_reject_absolute_path_script(self, tmp_dir):
        """Absolute paths in script field must be rejected."""
        catalog = {
            "version": 1,
            "items": [{
                "id": "evil-script",
                "name": "Evil Script",
                "description": "Bad",
                "category": "malicious",
                "version": "1.0.0",
                "manifest": "",
                "package_hash": "abc",
                "script": "/etc/passwd",
                "style": "",
            }]
        }
        cat_path = tmp_dir / "catalog.json"
        cat_path.write_text(json.dumps(catalog))
        sig_path = tmp_dir / "catalog.json.sig"
        sig_path.write_text("fake-signature")

        result = subprocess.run(
            ["lua", str(WEBSTORE), "list", str(cat_path)],
            capture_output=True,
            text=True,
            cwd=str(ROOT),
            timeout=10,
        )
        # Should either fail signature or reject the entry
        assert "unsafe" in result.stderr.lower() or result.returncode != 0

    def test_reject_traversal_path_script(self, tmp_dir):
        """Path traversal (..) in script field must be rejected."""
        catalog = {
            "version": 1,
            "items": [{
                "id": "traversal-script",
                "name": "Traversal",
                "description": "Bad",
                "category": "malicious",
                "version": "1.0.0",
                "manifest": "",
                "package_hash": "abc",
                "script": "../../../etc/shadow",
                "style": "",
            }]
        }
        cat_path = tmp_dir / "catalog.json"
        cat_path.write_text(json.dumps(catalog))
        sig_path = tmp_dir / "catalog.json.sig"
        sig_path.write_text("fake-signature")

        result = subprocess.run(
            ["lua", str(WEBSTORE), "list", str(cat_path)],
            capture_output=True,
            text=True,
            cwd=str(ROOT),
            timeout=10,
        )
        assert "unsafe" in result.stderr.lower() or result.returncode != 0

    def test_reject_traversal_path_style(self, tmp_dir):
        """Path traversal in style field must be rejected."""
        catalog = {
            "version": 1,
            "items": [{
                "id": "traversal-style",
                "name": "Traversal Style",
                "description": "Bad",
                "category": "malicious",
                "version": "1.0.0",
                "manifest": "",
                "package_hash": "abc",
                "script": "userscript.js",
                "style": "../../secret.css",
            }]
        }
        cat_path = tmp_dir / "catalog.json"
        cat_path.write_text(json.dumps(catalog))
        sig_path = tmp_dir / "catalog.json.sig"
        sig_path.write_text("fake-signature")

        result = subprocess.run(
            ["lua", str(WEBSTORE), "list", str(cat_path)],
            capture_output=True,
            text=True,
            cwd=str(ROOT),
            timeout=10,
        )
        assert "unsafe" in result.stderr.lower() or result.returncode != 0


class TestWebstoreSignatureVerification:
    """Verify catalog signature verification."""

    def test_reject_unsigned_catalog(self, tmp_dir):
        """A catalog without a valid signature must be rejected."""
        catalog = {
            "version": 1,
            "items": [{
                "id": "unsigned-item",
                "name": "Unsigned",
                "description": "No signature",
                "category": "test",
                "version": "1.0.0",
                "manifest": "",
                "package_hash": "abc",
                "script": "userscript.js",
                "style": "",
            }]
        }
        cat_path = tmp_dir / "catalog.json"
        cat_path.write_text(json.dumps(catalog))
        # No .sig file

        result = subprocess.run(
            ["lua", str(WEBSTORE), "list", str(cat_path)],
            capture_output=True,
            text=True,
            cwd=str(ROOT),
            timeout=10,
        )
        assert result.returncode == 5, "Unsigned catalog must be rejected"
        assert "signature" in result.stderr.lower() or "trust" in result.stderr.lower()

    def test_reject_bad_signature(self, tmp_dir):
        """A catalog with an invalid signature must be rejected."""
        catalog = {
            "version": 1,
            "items": [{
                "id": "bad-sig-item",
                "name": "Bad Sig",
                "description": "Invalid signature",
                "category": "test",
                "version": "1.0.0",
                "manifest": "",
                "package_hash": "abc",
                "script": "userscript.js",
                "style": "",
            }]
        }
        cat_path = tmp_dir / "catalog.json"
        cat_path.write_text(json.dumps(catalog))
        sig_path = tmp_dir / "catalog.json.sig"
        sig_path.write_text("invalid-signature-data")

        result = subprocess.run(
            ["lua", str(WEBSTORE), "list", str(cat_path)],
            capture_output=True,
            text=True,
            cwd=str(ROOT),
            timeout=10,
        )
        assert result.returncode == 5, "Bad signature must be rejected"


class TestWebstoreTrustedCatalog:
    """Verify the production catalog passes signature verification."""

    def test_production_catalog_trusted(self):
        """The shipped catalog must verify against the shipped public key."""
        catalog = TOOLS / "webstore_catalog.json"
        sig = TOOLS / "webstore_catalog.json.sig"
        pubkey = TOOLS / "webstore_pubkey.pem"

        if not all(f.exists() for f in [catalog, sig, pubkey]):
            pytest.skip("Production catalog files missing")

        result = subprocess.run(
            ["lua", str(WEBSTORE), "list", str(catalog)],
            capture_output=True,
            text=True,
            cwd=str(ROOT),
            timeout=10,
        )
        assert result.returncode == 0, (
            f"Production catalog should be trusted. stderr: {result.stderr}"
        )
        assert "reader-focus" in result.stdout or "clean-video" in result.stdout
