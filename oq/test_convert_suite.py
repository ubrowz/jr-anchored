"""
OQ test suite — Data conversion scripts (Python).

Covers: jrc_convert_csv, jrc_convert_txt
"""
import sys

# Force UTF-8 stdout/stderr on Windows (cp1252 cannot encode emoji)
if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if sys.stderr.encoding and sys.stderr.encoding.lower() != "utf-8":
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

import os
import csv
import glob
from conftest import run, combined, DATA_DIR


def data(name):
    return os.path.join(DATA_DIR, name)


# ===========================================================================
# jrc_convert_csv (TC-CCSV-001 .. 008)
# ===========================================================================

class TestConvertCsv:

    def _clean_output_csvs(self, stem):
        """Remove any output CSVs matching the given stem in DATA_DIR."""
        for f in glob.glob(os.path.join(DATA_DIR, f"{stem}*.csv")):
            os.remove(f)

    def test_tc_ccsv_001_column_by_name_auto_delimiter(self):
        """TC-CCSV-001: Column by name, auto-detect tab delimiter, 3 header lines"""
        self._clean_output_csvs("convert_multicolumn_colForceN")
        r = run("jrc_convert_csv.py",
                data("convert_multicolumn.txt"), "ForceN", "3")
        assert r.returncode == 0
        out = combined(r)
        assert "✅" in out or "saved" in out.lower()
        # Find output file
        output_files = glob.glob(os.path.join(DATA_DIR, "convert_multicolumn*ForceN*.csv")) + \
                       glob.glob(os.path.join(DATA_DIR, "convert_multicolumn*col*.csv"))
        assert len(output_files) >= 1
        with open(output_files[0]) as f:
            header = f.readline().strip()
        assert "id" in header and "value" in header

    def test_tc_ccsv_002_column_by_number(self):
        """TC-CCSV-002: Column by number 2 = ForceN → exit 0"""
        r = run("jrc_convert_csv.py",
                data("convert_multicolumn.txt"), "2", "3")
        assert r.returncode == 0

    def test_tc_ccsv_003_forced_tab_delimiter(self):
        """TC-CCSV-003: Explicit tab delimiter → exit 0, same result as auto"""
        r = run("jrc_convert_csv.py",
                data("convert_multicolumn.txt"), "ForceN", "3", "tab")
        assert r.returncode == 0

    def test_tc_ccsv_004_skip_lines_exceeds_file(self):
        """TC-CCSV-004: skip_lines=999 → non-zero exit, mentions skip_lines"""
        r = run("jrc_convert_csv.py",
                data("convert_multicolumn.txt"), "ForceN", "999")
        assert r.returncode != 0
        assert "skip" in combined(r).lower()

    def test_tc_ccsv_005_column_name_not_found(self):
        """TC-CCSV-005: NonExistentCol → non-zero exit, mentions 'not found'"""
        r = run("jrc_convert_csv.py",
                data("convert_multicolumn.txt"), "NonExistentCol", "3")
        assert r.returncode != 0
        assert "not found" in combined(r).lower()

    def test_tc_ccsv_006_file_not_found(self):
        """TC-CCSV-006: nonexistent input file → non-zero exit, mentions 'not found'"""
        r = run("jrc_convert_csv.py", "nonexistent.txt", "ForceN", "0")
        assert r.returncode != 0
        assert "not found" in combined(r).lower()

    def test_tc_ccsv_007_invalid_delimiter(self):
        """TC-CCSV-007: delimiter='pipe' → non-zero exit, mentions 'delimiter'"""
        r = run("jrc_convert_csv.py",
                data("convert_multicolumn.txt"), "ForceN", "3", "pipe")
        assert r.returncode != 0
        assert "delimiter" in combined(r).lower()

    def test_tc_ccsv_008_missing_arguments(self):
        """TC-CCSV-008: only 2 arguments → non-zero exit, mentions 'Usage'"""
        r = run("jrc_convert_csv.py",
                data("convert_multicolumn.txt"), "ForceN")
        assert r.returncode != 0
        assert "usage" in combined(r).lower()


# ===========================================================================
# jrc_convert_txt (TC-CTXT-001 .. 007)
# ===========================================================================

class TestConvertTxt:

    def _clean_output_csvs(self):
        for f in glob.glob(os.path.join(DATA_DIR, "convert_singlecolumn*.csv")):
            os.remove(f)

    def test_tc_ctxt_001_full_file_no_range(self):
        """TC-CTXT-001: Full 200-line file → exit 0, 200 data rows, ✅"""
        self._clean_output_csvs()
        r = run("jrc_convert_txt.py", data("convert_singlecolumn.txt"))
        assert r.returncode == 0
        assert "✅" in combined(r) or "saved" in combined(r).lower()
        # Find output file
        files = glob.glob(os.path.join(DATA_DIR, "convert_singlecolumn*.csv"))
        assert len(files) >= 1
        with open(files[0]) as f:
            rows = list(csv.reader(f))
        assert len(rows) == 201  # header + 200 data rows

    def test_tc_ctxt_002_line_range_specified(self):
        """TC-CTXT-002: Lines 50-100 → 51 data rows, filename contains 'lines50to100'"""
        self._clean_output_csvs()
        r = run("jrc_convert_txt.py",
                data("convert_singlecolumn.txt"), "50", "100")
        assert r.returncode == 0
        files = glob.glob(os.path.join(DATA_DIR, "convert_singlecolumn*.csv"))
        assert len(files) >= 1
        with open(files[0]) as f:
            rows = list(csv.reader(f))
        assert len(rows) == 52  # header + 51 data rows (50..100 inclusive)

    def test_tc_ctxt_003_start_line_only(self):
        """TC-CTXT-003: Start line 150, no end → lines 150-200 = 51 rows"""
        self._clean_output_csvs()
        r = run("jrc_convert_txt.py",
                data("convert_singlecolumn.txt"), "150")
        assert r.returncode == 0
        files = glob.glob(os.path.join(DATA_DIR, "convert_singlecolumn*.csv"))
        assert len(files) >= 1
        with open(files[0]) as f:
            rows = list(csv.reader(f))
        assert len(rows) == 52  # header + 51 rows (150..200 inclusive)

    def test_tc_ctxt_004_start_line_exceeds_file(self):
        """TC-CTXT-004: start_line=500 > 200 lines → non-zero exit"""
        r = run("jrc_convert_txt.py",
                data("convert_singlecolumn.txt"), "500")
        assert r.returncode != 0
        out = combined(r).lower()
        assert "start_line" in out or "exceeds" in out or "start" in out

    def test_tc_ctxt_005_end_line_lt_start_line(self):
        """TC-CTXT-005: end_line=50 < start_line=100 → non-zero exit"""
        r = run("jrc_convert_txt.py",
                data("convert_singlecolumn.txt"), "100", "50")
        assert r.returncode != 0
        assert "end_line" in combined(r).lower() or "end" in combined(r).lower()

    def test_tc_ctxt_006_file_not_found(self):
        """TC-CTXT-006: nonexistent file → non-zero exit, mentions 'not found'"""
        r = run("jrc_convert_txt.py", "nonexistent.txt")
        assert r.returncode != 0
        assert "not found" in combined(r).lower()

    def test_tc_ctxt_007_missing_arguments(self):
        """TC-CTXT-007: no arguments → non-zero exit, mentions 'Usage'"""
        r = run("jrc_convert_txt.py")
        assert r.returncode != 0
        assert "usage" in combined(r).lower()
