"""Tests for Nim sidecar tools: ed25519_verify and history_indexer.

Verifies the compiled binaries work correctly.
"""

import subprocess
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
TOOLS = ROOT / "tools"
BUILD = ROOT / "build"


@pytest.fixture
def tmp_dir():
    with tempfile.TemporaryDirectory() as d:
        yield Path(d)


class TestEd25519Verify:
    """Verify the ed25519 signature verification tool."""

    def test_verify_ok_on_valid_signature(self, tmp_dir):
        """A correctly signed file must verify ok."""
        # Generate a key pair and sign a message
        privkey = tmp_dir / "priv.pem"
        pubkey = tmp_dir / "pub.pem"
        subprocess.run(
            ["openssl", "genpkey", "-algorithm", "Ed25519",
             "-out", str(privkey)],
            capture_output=True, timeout=10,
        )
        subprocess.run(
            ["openssl", "pkey", "-in", str(privkey), "-pubout",
             "-out", str(pubkey)],
            capture_output=True, timeout=10,
        )

        message = tmp_dir / "message.txt"
        message.write_text("Hello, OBrowser!")
        sig = tmp_dir / "message.txt.sig"

        subprocess.run(
            ["openssl", "pkeyutl", "-sign", "-inkey", str(privkey),
             "-rawin", "-in", str(message), "-out", str(sig)],
            capture_output=True, timeout=10,
        )

        verifier = BUILD / "ed25519_verify"
        result = subprocess.run(
            [str(verifier), str(pubkey), str(message), str(sig)],
            capture_output=True,
            text=True,
            cwd=str(ROOT),
            timeout=10,
        )
        assert result.returncode == 0
        assert "verify=ok" in result.stdout

    def test_verify_fail_on_tampered_message(self, tmp_dir):
        """A tampered message must fail verification."""
        privkey = tmp_dir / "priv.pem"
        pubkey = tmp_dir / "pub.pem"
        subprocess.run(
            ["openssl", "genpkey", "-algorithm", "Ed25519", "-out", str(privkey)],
            capture_output=True, timeout=10,
        )
        subprocess.run(
            ["openssl", "pkey", "-in", str(privkey), "-pubout", "-out", str(pubkey)],
            capture_output=True, timeout=10,
        )

        message = tmp_dir / "message.txt"
        message.write_text("Original message")
        sig = tmp_dir / "message.txt.sig"

        subprocess.run(
            ["openssl", "pkeyutl", "-sign", "-inkey", str(privkey),
             "-rawin", "-in", str(message), "-out", str(sig)],
            capture_output=True, timeout=10,
        )

        # Tamper with the message
        message.write_text("Tampered message")

        verifier = BUILD / "ed25519_verify"
        result = subprocess.run(
            [str(verifier), str(pubkey), str(message), str(sig)],
            capture_output=True,
            text=True,
            cwd=str(ROOT),
            timeout=10,
        )
        assert result.returncode != 0
        assert "verify=fail" in result.stdout

    def test_verify_fail_on_missing_file(self, tmp_dir):
        """Missing files must be reported as failure."""
        verifier = BUILD / "ed25519_verify"
        result = subprocess.run(
            [str(verifier), str(tmp_dir / "nokey.pem"),
             str(tmp_dir / "nomsg.txt"), str(tmp_dir / "nosig.sig")],
            capture_output=True,
            text=True,
            cwd=str(ROOT),
            timeout=10,
        )
        assert result.returncode == 2
        assert "verify=fail" in result.stdout
        assert "missing_file" in result.stdout

    def test_production_catalog_signature_valid(self):
        """The production catalog must verify against the production pubkey."""
        catalog = TOOLS / "webstore_catalog.json"
        sig = TOOLS / "webstore_catalog.json.sig"
        pubkey = TOOLS / "webstore_pubkey.pem"
        verifier = BUILD / "ed25519_verify"

        if not all(f.exists() for f in [catalog, sig, pubkey]):
            pytest.skip("Production catalog files missing")

        result = subprocess.run(
            [str(verifier), str(pubkey), str(catalog), str(sig)],
            capture_output=True,
            text=True,
            cwd=str(ROOT),
            timeout=10,
        )
        assert result.returncode == 0, (
            f"Production catalog signature invalid: {result.stdout} {result.stderr}"
        )
        assert "verify=ok" in result.stdout


class TestHistoryIndexer:
    """Verify the history indexer Nim sidecar."""

    def test_index_creation(self, tmp_dir):
        """Indexer should create a domain visit index."""
        history = tmp_dir / "history.ini"
        history.write_text(
            "[history-000]\nuri=https://example.com/page1\n\n"
            "[history-001]\nuri=https://example.com/page2\n\n"
            "[history-002]\nuri=https://other.com/\n"
        )
        out = tmp_dir / "history.index"

        indexer = BUILD / "history_indexer"
        result = subprocess.run(
            [str(indexer), str(history), str(out)],
            capture_output=True,
            text=True,
            cwd=str(ROOT),
            timeout=10,
        )
        assert result.returncode == 0
        assert out.exists()
        content = out.read_text()
        assert "example.com" in content
        assert "other.com" in content

    def test_index_empty_history(self, tmp_dir):
        """Indexer should handle empty history gracefully."""
        history = tmp_dir / "history.ini"
        history.write_text("")
        out = tmp_dir / "history.index"

        indexer = BUILD / "history_indexer"
        result = subprocess.run(
            [str(indexer), str(history), str(out)],
            capture_output=True,
            text=True,
            cwd=str(ROOT),
            timeout=10,
        )
        assert result.returncode == 0

    def test_index_missing_history(self, tmp_dir):
        """Indexer should create empty index for missing file."""
        history = tmp_dir / "nonexistent.ini"
        out = tmp_dir / "history.index"

        indexer = BUILD / "history_indexer"
        result = subprocess.run(
            [str(indexer), str(history), str(out)],
            capture_output=True,
            text=True,
            cwd=str(ROOT),
            timeout=10,
        )
        assert result.returncode == 0
        assert out.exists()
