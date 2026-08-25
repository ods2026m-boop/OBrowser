"""Tests for the security_guard Nim sidecar.

Covers the URL filtering policy enforcement that blocks dangerous navigation.
"""

import pytest

from conftest import run_tool, parse_keyval


class TestSecurityGuardSchemeBlocking:
    """Verify dangerous URI schemes are blocked."""

    def test_block_javascript_scheme(self, security_guard, blocklist_file, whitelist_file):
        rc, stdout, _ = run_tool([
            str(security_guard),
            "javascript:alert(1)",
            str(blocklist_file),
            str(whitelist_file),
        ])
        out = parse_keyval(stdout)
        assert rc == 0
        assert out["decision"] == "block"
        assert "javascript" in out["reason"]

    def test_block_data_text_html(self, security_guard, blocklist_file, whitelist_file):
        rc, stdout, _ = run_tool([
            str(security_guard),
            "data:text/html,<script>alert(1)</script>",
            str(blocklist_file),
            str(whitelist_file),
        ])
        out = parse_keyval(stdout)
        assert out["decision"] == "block"
        assert "data html" in out["reason"]

    def test_allow_file_scheme(self, security_guard, blocklist_file, whitelist_file):
        rc, stdout, _ = run_tool([
            str(security_guard),
            "file:///home/user/document.html",
            str(blocklist_file),
            str(whitelist_file),
        ])
        out = parse_keyval(stdout)
        assert out["decision"] == "allow"

    def test_allow_empty_url(self, security_guard, blocklist_file, whitelist_file):
        rc, stdout, _ = run_tool([
            str(security_guard),
            "",
            str(blocklist_file),
            str(whitelist_file),
        ])
        out = parse_keyval(stdout)
        assert out["decision"] == "allow"
        assert out["reason"] == "empty"


class TestSecurityGuardPhishingDetection:
    """Verify phishing-related heuristics."""

    def test_block_url_with_userinfo(self, security_guard, blocklist_file, whitelist_file):
        rc, stdout, _ = run_tool([
            str(security_guard),
            "https://trusted.com@evil.com/login",
            str(blocklist_file),
            str(whitelist_file),
        ])
        out = parse_keyval(stdout)
        assert out["decision"] == "block"
        assert "userinfo" in out["reason"]
        assert out["risk"] == "high"

    def test_block_punycode_host(self, security_guard, blocklist_file, whitelist_file):
        rc, stdout, _ = run_tool([
            str(security_guard),
            "https://xn--80ak6aa92e.com/",
            str(blocklist_file),
            str(whitelist_file),
        ])
        out = parse_keyval(stdout)
        assert out["decision"] == "block"
        assert "phishing" in out["reason"]

    def test_block_confusable_delimiters(self, security_guard, blocklist_file, whitelist_file):
        rc, stdout, _ = run_tool([
            str(security_guard),
            "https://login-paypal.com/",
            str(blocklist_file),
            str(whitelist_file),
        ])
        out = parse_keyval(stdout)
        assert out["decision"] == "block"
        assert "confusable" in out["reason"] or "phishing" in out["reason"]

    def test_block_high_entropy_hostname(self, security_guard, blocklist_file, whitelist_file):
        rc, stdout, _ = run_tool([
            str(security_guard),
            "https://a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7.com/",
            str(blocklist_file),
            str(whitelist_file),
        ])
        out = parse_keyval(stdout)
        assert out["decision"] == "block"
        assert "entropy" in out["reason"]

    def test_block_risky_tld(self, security_guard, blocklist_file, whitelist_file):
        rc, stdout, _ = run_tool([
            str(security_guard),
            "https://malware.example.zip/",
            str(blocklist_file),
            str(whitelist_file),
        ])
        out = parse_keyval(stdout)
        assert out["decision"] == "block"
        assert "tld" in out["reason"]


class TestSecurityGuardMixedContent:
    """Verify mixed-content and insecure delivery protections."""

    def test_block_mixed_content_js(self, security_guard, blocklist_file, whitelist_file):
        rc, stdout, _ = run_tool([
            str(security_guard),
            "http://cdn.example.com/lib.js",
            str(blocklist_file),
            str(whitelist_file),
            "https://secure.example.com/",
        ])
        out = parse_keyval(stdout)
        assert out["decision"] == "block"
        assert "mixed content" in out["reason"]

    def test_block_insecure_executable(self, security_guard, blocklist_file, whitelist_file):
        rc, stdout, _ = run_tool([
            str(security_guard),
            "http://download.example.com/setup.exe",
            str(blocklist_file),
            str(whitelist_file),
        ])
        out = parse_keyval(stdout)
        assert out["decision"] == "block"
        assert "executable" in out["reason"]

    def test_block_control_chars_in_url(self, security_guard, blocklist_file, whitelist_file):
        rc, stdout, _ = run_tool([
            str(security_guard),
            "https://example.com/path%00.html",
            str(blocklist_file),
            str(whitelist_file),
        ])
        out = parse_keyval(stdout)
        assert out["decision"] == "block"
        assert "control" in out["reason"] or "character" in out["reason"]


class TestSecurityGuardTraversal:
    """Verify path traversal protection."""

    def test_block_path_traversal(self, security_guard, blocklist_file, whitelist_file):
        rc, stdout, _ = run_tool([
            str(security_guard),
            "https://example.com/../../etc/passwd",
            str(blocklist_file),
            str(whitelist_file),
        ])
        out = parse_keyval(stdout)
        assert out["decision"] == "block"
        assert "traversal" in out["reason"]

    def test_block_double_encoded_traversal(self, security_guard, blocklist_file, whitelist_file):
        rc, stdout, _ = run_tool([
            str(security_guard),
            "https://example.com/%252e%252e/%252e%252e/etc/passwd",
            str(blocklist_file),
            str(whitelist_file),
        ])
        out = parse_keyval(stdout)
        assert out["decision"] == "block"
        assert "traversal" in out["reason"]


class TestSecurityGuardLocalNetwork:
    """Verify plaintext local network protection."""

    def test_block_plaintext_localhost(self, security_guard, blocklist_file, whitelist_file):
        rc, stdout, _ = run_tool([
            str(security_guard),
            "http://127.0.0.1/admin",
            str(blocklist_file),
            str(whitelist_file),
        ])
        out = parse_keyval(stdout)
        assert out["decision"] == "block"
        assert "local" in out["reason"] or "plaintext" in out["reason"]

    def test_block_plaintext_private_ip(self, security_guard, blocklist_file, whitelist_file):
        rc, stdout, _ = run_tool([
            str(security_guard),
            "http://192.168.1.1/config",
            str(blocklist_file),
            str(whitelist_file),
        ])
        out = parse_keyval(stdout)
        assert out["decision"] == "block"


class TestSecurityGuardBlocklist:
    """Verify blocklist enforcement."""

    def test_block_blocked_domain(self, security_guard, blocklist_file, whitelist_file):
        rc, stdout, _ = run_tool([
            str(security_guard),
            "https://malware.example/page",
            str(blocklist_file),
            str(whitelist_file),
        ])
        out = parse_keyval(stdout)
        assert out["decision"] == "block"
        assert "blocklist" in out["reason"]

    def test_allow_whitelisted_domain(self, security_guard, blocklist_file, whitelist_file):
        rc, stdout, _ = run_tool([
            str(security_guard),
            "https://trustedsite.com/safe",
            str(blocklist_file),
            str(whitelist_file),
        ])
        out = parse_keyval(stdout)
        assert out["decision"] == "allow"


class TestSecurityGuardCrossScheme:
    """Verify cross-scheme downgrade protection."""

    def test_block_cross_scheme_downgrade(self, security_guard, blocklist_file, whitelist_file):
        rc, stdout, _ = run_tool([
            str(security_guard),
            "ftp://files.example.com/download",
            str(blocklist_file),
            str(whitelist_file),
            "https://secure.example.com/",
        ])
        out = parse_keyval(stdout)
        assert out["decision"] == "block"
        assert "downgrade" in out["reason"] or "scheme" in out["reason"]
