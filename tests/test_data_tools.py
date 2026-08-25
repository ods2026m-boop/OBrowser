"""Tests for the history_report.lua and bookmarks_tool.lua tools.

Verifies correct parsing and JSON/INI conversion.
"""

import json
import subprocess
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
TOOLS = ROOT / "tools"
HISTORY_REPORT = TOOLS / "history_report.lua"
BOOKMARKS_TOOL = TOOLS / "bookmarks_tool.lua"


@pytest.fixture
def tmp_dir():
    with tempfile.TemporaryDirectory() as d:
        yield Path(d)


class TestHistoryReport:
    """Verify history report generation."""

    def test_history_report_text(self, tmp_dir):
        history = tmp_dir / "history.ini"
        history.write_text(
            "[history-000]\n"
            "uri=https://example.com\n"
            "title=Example\n"
            "visited_at=1700000000\n"
            "visit_count=5\n"
            "\n"
            "[history-001]\n"
            "uri=https://another.com\n"
            "title=Another\n"
            "visited_at=1700000100\n"
            "visit_count=3\n"
        )
        result = subprocess.run(
            ["lua", str(HISTORY_REPORT), str(history), "10", "10"],
            capture_output=True,
            text=True,
            cwd=str(ROOT),
            timeout=10,
        )
        assert result.returncode == 0
        assert "example.com" in result.stdout
        assert "another.com" in result.stdout

    def test_history_report_json(self, tmp_dir):
        history = tmp_dir / "history.ini"
        history.write_text(
            "[history-000]\n"
            "uri=https://example.com\n"
            "title=Example\n"
            "visited_at=1700000000\n"
            "visit_count=5\n"
        )
        out_path = tmp_dir / "report.json"
        result = subprocess.run(
            ["lua", str(HISTORY_REPORT), str(history), "10", "10",
             "--json", "--output", str(out_path)],
            capture_output=True,
            text=True,
            cwd=str(ROOT),
            timeout=10,
        )
        assert result.returncode == 0
        assert out_path.exists()
        data = json.loads(out_path.read_text())
        assert "top_domains" in data
        assert "latest_entries" in data

    def test_history_report_domain_grouping(self, tmp_dir):
        history = tmp_dir / "history.ini"
        history.write_text(
            "[history-000]\nuri=https://example.com/a\nvisit_count=2\nvisited_at=1700000000\n\n"
            "[history-001]\nuri=https://example.com/b\nvisit_count=3\nvisited_at=1700000100\n\n"
            "[history-002]\nuri=https://other.com/\nvisit_count=1\nvisited_at=1700000200\n"
        )
        result = subprocess.run(
            ["lua", str(HISTORY_REPORT), str(history), "10", "10"],
            capture_output=True,
            text=True,
            cwd=str(ROOT),
            timeout=10,
        )
        assert result.returncode == 0
        assert "example.com" in result.stdout


class TestBookmarksTool:
    """Verify bookmark import/export."""

    def test_export_bookmarks(self, tmp_dir):
        bookmarks = tmp_dir / "bookmarks.ini"
        bookmarks.write_text(
            "[bookmark-000]\n"
            "uri=https://example.com\n"
            "title=Example Site\n"
            "added_at=1700000000\n"
        )
        out_json = tmp_dir / "bookmarks.json"
        result = subprocess.run(
            ["lua", str(BOOKMARKS_TOOL), "export", str(bookmarks), str(out_json)],
            capture_output=True,
            text=True,
            cwd=str(ROOT),
            timeout=10,
        )
        assert result.returncode == 0
        assert out_json.exists()
        data = json.loads(out_json.read_text())
        assert len(data) == 1
        assert data[0]["uri"] == "https://example.com"
        assert data[0]["title"] == "Example Site"

    def test_import_bookmarks(self, tmp_dir):
        bookmarks_json = tmp_dir / "bookmarks.json"
        bookmarks_json.write_text(json.dumps([
            {"uri": "https://imported.com", "title": "Imported", "added_at": 1700000000}
        ]))
        out_ini = tmp_dir / "bookmarks.ini"
        result = subprocess.run(
            ["lua", str(BOOKMARKS_TOOL), "import", str(bookmarks_json), str(out_ini)],
            capture_output=True,
            text=True,
            cwd=str(ROOT),
            timeout=10,
        )
        assert result.returncode == 0
        assert out_ini.exists()
        content = out_ini.read_text()
        assert "imported.com" in content
        assert "Imported" in content

    def test_bookmark_roundtrip(self, tmp_dir):
        """Export then import should preserve data."""
        original = tmp_dir / "original.ini"
        original.write_text(
            "[bookmark-000]\nuri=https://test.com\ntitle=Test\nadded_at=1700000000\n"
        )
        json_file = tmp_dir / "export.json"
        imported = tmp_dir / "imported.ini"

        subprocess.run(
            ["lua", str(BOOKMARKS_TOOL), "export", str(original), str(json_file)],
            capture_output=True, cwd=str(ROOT), timeout=10,
        )
        subprocess.run(
            ["lua", str(BOOKMARKS_TOOL), "import", str(json_file), str(imported)],
            capture_output=True, cwd=str(ROOT), timeout=10,
        )

        content = imported.read_text()
        assert "test.com" in content
        assert "Test" in content
