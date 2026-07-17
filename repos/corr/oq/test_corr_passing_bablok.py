"""
OQ test suite — Corr module: jrc_corr_passing_bablok

Maps to validation plan JR-VP-CORR-001 as follows:

  TC-CORR-PB-001  Valid input (corr_method_comp.csv) -> exit 0, "Passing-Bablok" in output
  TC-CORR-PB-002  Slope value present in output (look for "Slope" label)
  TC-CORR-PB-003  Intercept value present in output
  TC-CORR-PB-004  Cusum test result present in output
  TC-CORR-PB-005  Proportionality test result present (look for "slope" and "1")
  TC-CORR-PB-006  PNG saved to ~/Downloads/ with pattern *_jrc_corr_passing_bablok.png
  TC-CORR-PB-007  No arguments -> non-zero exit
  TC-CORR-PB-008  File not found -> non-zero exit
  TC-CORR-PB-009  n < 3 -> non-zero exit
  TC-CORR-PB-010  Non-numeric column -> non-zero exit
  TC-CORR-PB-011  Slope approximately 1.1 for corr_method_comp.csv (output contains "1.1")
  TC-CORR-PB-012  Direct Rscript call without RENV_PATHS_ROOT -> non-zero exit
"""
import sys

# Force UTF-8 stdout/stderr on Windows (cp1252 cannot encode emoji)
if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if sys.stderr.encoding and sys.stderr.encoding.lower() != "utf-8":
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

import glob
import os
import subprocess
import time

from conftest import PROJECT_ROOT, MODULE_ROOT, run, combined, data, RSCRIPT_BIN


# Where the script under test writes its artifacts. The OQ runner sets
# JR_OUT_DIR to this run's own folder; the default matches the scripts'
# own default, so a suite run by hand still looks in ~/Downloads.
DOWNLOADS = os.environ.get("JR_OUT_DIR") or os.path.expanduser("~/Downloads")


def _recent_png(pattern, t_start):
    return [
        f for f in glob.glob(os.path.join(DOWNLOADS, pattern))
        if os.path.getmtime(f) >= t_start - 1.0
    ]


class TestCorrPassingBablok:

    def test_tc_corr_pb_001_happy_path_exits_zero(self):
        """
        TC-CORR-PB-001:
        Valid input (corr_method_comp.csv) -> exit 0.
        Output must contain "Passing-Bablok".
        """
        r = run("jrc_corr_passing_bablok.R", data("corr_method_comp.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Passing-Bablok" in out, \
            f"Expected 'Passing-Bablok' in output:\n{out}"

    def test_tc_corr_pb_002_slope_label_present(self):
        """
        TC-CORR-PB-002:
        Output must contain a "Slope" label.
        """
        r = run("jrc_corr_passing_bablok.R", data("corr_method_comp.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Slope" in out, \
            f"Expected 'Slope' label in output:\n{out}"

    def test_tc_corr_pb_003_intercept_present(self):
        """
        TC-CORR-PB-003:
        Output must contain an "Intercept" label.
        """
        r = run("jrc_corr_passing_bablok.R", data("corr_method_comp.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Intercept" in out, \
            f"Expected 'Intercept' label in output:\n{out}"

    def test_tc_corr_pb_004_cusum_present(self):
        """
        TC-CORR-PB-004:
        Output must contain the Cusum linearity test result.
        """
        r = run("jrc_corr_passing_bablok.R", data("corr_method_comp.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Cusum" in out or "cusum" in out.lower() or "cumulative" in out.lower(), \
            f"Expected Cusum test result in output:\n{out}"

    def test_tc_corr_pb_005_proportionality_test_present(self):
        """
        TC-CORR-PB-005:
        Output must contain proportionality test result referencing slope and 1.
        """
        r = run("jrc_corr_passing_bablok.R", data("corr_method_comp.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert ("slope" in out.lower() or "Slope" in out) and "1" in out, \
            f"Expected proportionality test (slope = 1) in output:\n{out}"

    def test_tc_corr_pb_006_png_created(self):
        """
        TC-CORR-PB-006:
        A PNG file matching *_jrc_corr_passing_bablok.png must be created in
        ~/Downloads/ during this run.
        """
        t_start = time.time()
        r = run("jrc_corr_passing_bablok.R", data("corr_method_comp.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        recent = _recent_png("*_jrc_corr_passing_bablok.png", t_start)
        assert recent, (
            f"No *_jrc_corr_passing_bablok.png found in ~/Downloads/ after run\n"
            f"  DOWNLOADS={DOWNLOADS!r} (exists={os.path.isdir(DOWNLOADS)})\n"
            f"  All matches (any age): {glob.glob(os.path.join(DOWNLOADS, '*_jrc_corr_passing_bablok.png'))!r}\n"
            f"  Script output: {combined(r)}"
        )

    def test_tc_corr_pb_007_no_arguments(self):
        """
        TC-CORR-PB-007:
        Calling with no arguments must exit non-zero.
        """
        r = run("jrc_corr_passing_bablok.R")
        assert r.returncode != 0, "Expected non-zero exit with no arguments"

    def test_tc_corr_pb_008_file_not_found(self):
        """
        TC-CORR-PB-008:
        Providing a non-existent file must exit non-zero.
        """
        r = run("jrc_corr_passing_bablok.R", "nonexistent_file_xyz.csv")
        assert r.returncode != 0, \
            f"Expected non-zero exit for missing file:\n{combined(r)}"

    def test_tc_corr_pb_009_n_less_than_3(self):
        """
        TC-CORR-PB-009:
        Input with only 2 rows (n < 3) must exit non-zero.
        """
        r = run("jrc_corr_passing_bablok.R", data("corr_small.csv"))
        assert r.returncode != 0, \
            f"Expected non-zero exit when n < 3:\n{combined(r)}"

    def test_tc_corr_pb_010_nonnumeric_column(self):
        """
        TC-CORR-PB-010:
        Non-numeric y column must exit non-zero.
        """
        r = run("jrc_corr_passing_bablok.R", data("corr_nonnumeric.csv"))
        assert r.returncode != 0, \
            f"Expected non-zero exit for non-numeric column:\n{combined(r)}"

    def test_tc_corr_pb_011_slope_approximately_1_1(self):
        """
        TC-CORR-PB-011:
        For corr_method_comp.csv (y ≈ 1.1x + 2), the slope should be ≈ 1.1.
        Output must contain "1.1".
        """
        r = run("jrc_corr_passing_bablok.R", data("corr_method_comp.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "1.1" in out, \
            f"Expected slope ≈ 1.1 (contains '1.1') in output:\n{out}"

    def test_tc_corr_pb_012_bypass_protection(self):
        """
        TC-CORR-PB-012:
        Calling jrc_corr_passing_bablok.R directly via Rscript without RENV_PATHS_ROOT
        must exit non-zero.
        """
        script = os.path.join(MODULE_ROOT, "R", "jrc_corr_passing_bablok.R")
        env = {k: v for k, v in os.environ.items() if k != "RENV_PATHS_ROOT"}
        result = subprocess.run(
            [RSCRIPT_BIN, "--vanilla", script, data("corr_method_comp.csv")],
            capture_output=True,
            encoding="utf-8",
            env=env,
            cwd=PROJECT_ROOT,
        )
        assert result.returncode != 0, \
            "Expected non-zero exit when called without RENV_PATHS_ROOT"
        out = (result.stdout or "") + (result.stderr or "")
        assert "RENV_PATHS_ROOT" in out, \
            f"Expected 'RENV_PATHS_ROOT' in error output:\n{out}"
