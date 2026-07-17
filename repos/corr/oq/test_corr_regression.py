"""
OQ test suite — Corr module: jrc_corr_regression

Maps to validation plan JR-VP-CORR-001 as follows:

  TC-CORR-R-001  Valid input (corr_linear.csv) -> exit 0, "Regression" in output
  TC-CORR-R-002  Slope value present in output (look for "Slope" label)
  TC-CORR-R-003  Intercept value present in output
  TC-CORR-R-004  R-squared present in output
  TC-CORR-R-005  PNG saved to ~/Downloads/ with pattern *_jrc_corr_regression.png
  TC-CORR-R-006  No arguments -> non-zero exit
  TC-CORR-R-007  File not found -> non-zero exit
  TC-CORR-R-008  n < 3 -> non-zero exit
  TC-CORR-R-009  Non-numeric column -> non-zero exit
  TC-CORR-R-010  Slope approximately 2.0 for corr_linear.csv (output contains "1.9" or "2.0")
  TC-CORR-R-011  Direct Rscript call without RENV_PATHS_ROOT -> non-zero exit

Numeric correctness assertions (TC-CORR-R-012 to TC-CORR-R-014):

  Reference dataset: corr_exact_linear.csv — 10 points, y = 2x + 1 (x=1..10)
  Independent computation (exact OLS formulas):
    slope (b1)     = Sxy / Sxx  = 2.000 (exact for y=2x+1)
    intercept (b0) = mean(y) - b1*mean(x) = 1.000 (exact)
    R-squared      = r²         = 1.000 (exact for perfect linear data)

  TC-CORR-R-012  Slope (b1)     = 2.000 ± 0.001
  TC-CORR-R-013  Intercept (b0) = 1.000 ± 0.001
  TC-CORR-R-014  R-squared      = 1.000 ± 0.001
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

from conftest import PROJECT_ROOT, MODULE_ROOT, run, combined, data, extract_float, RSCRIPT_BIN


# Where the script under test writes its artifacts. The OQ runner sets
# JR_OUT_DIR to this run's own folder; the default matches the scripts'
# own default, so a suite run by hand still looks in ~/Downloads.
DOWNLOADS = os.environ.get("JR_OUT_DIR") or os.path.expanduser("~/Downloads")


def _recent_png(pattern, t_start):
    return [
        f for f in glob.glob(os.path.join(DOWNLOADS, pattern))
        if os.path.getmtime(f) >= t_start - 1.0
    ]


class TestCorrRegression:

    def test_tc_corr_r_001_happy_path_exits_zero(self):
        """
        TC-CORR-R-001:
        Valid input (corr_linear.csv) -> exit 0.
        Output must contain "Regression".
        """
        r = run("jrc_corr_regression.R", data("corr_linear.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Regression" in out, \
            f"Expected 'Regression' in output:\n{out}"

    def test_tc_corr_r_002_slope_label_present(self):
        """
        TC-CORR-R-002:
        Output must contain a "Slope" label.
        """
        r = run("jrc_corr_regression.R", data("corr_linear.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Slope" in out, \
            f"Expected 'Slope' label in output:\n{out}"

    def test_tc_corr_r_003_intercept_present(self):
        """
        TC-CORR-R-003:
        Output must contain an "Intercept" label.
        """
        r = run("jrc_corr_regression.R", data("corr_linear.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Intercept" in out, \
            f"Expected 'Intercept' label in output:\n{out}"

    def test_tc_corr_r_004_r_squared_present(self):
        """
        TC-CORR-R-004:
        Output must contain an R-squared value.
        """
        r = run("jrc_corr_regression.R", data("corr_linear.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "R-squared" in out or "r-squared" in out.lower(), \
            f"Expected 'R-squared' in output:\n{out}"

    def test_tc_corr_r_005_png_created(self):
        """
        TC-CORR-R-005:
        A PNG file matching *_jrc_corr_regression.png must be created in
        ~/Downloads/ during this run.
        """
        t_start = time.time()
        r = run("jrc_corr_regression.R", data("corr_linear.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        recent = _recent_png("*_jrc_corr_regression.png", t_start)
        assert recent, (
            f"No *_jrc_corr_regression.png found in ~/Downloads/ after run\n"
            f"  DOWNLOADS={DOWNLOADS!r} (exists={os.path.isdir(DOWNLOADS)})\n"
            f"  All matches (any age): {glob.glob(os.path.join(DOWNLOADS, '*_jrc_corr_regression.png'))!r}\n"
            f"  Script output: {combined(r)}"
        )

    def test_tc_corr_r_006_no_arguments(self):
        """
        TC-CORR-R-006:
        Calling with no arguments must exit non-zero.
        """
        r = run("jrc_corr_regression.R")
        assert r.returncode != 0, "Expected non-zero exit with no arguments"

    def test_tc_corr_r_007_file_not_found(self):
        """
        TC-CORR-R-007:
        Providing a non-existent file must exit non-zero.
        """
        r = run("jrc_corr_regression.R", "nonexistent_file_xyz.csv")
        assert r.returncode != 0, \
            f"Expected non-zero exit for missing file:\n{combined(r)}"

    def test_tc_corr_r_008_n_less_than_3(self):
        """
        TC-CORR-R-008:
        Input with only 2 rows (n < 3) must exit non-zero.
        """
        r = run("jrc_corr_regression.R", data("corr_small.csv"))
        assert r.returncode != 0, \
            f"Expected non-zero exit when n < 3:\n{combined(r)}"

    def test_tc_corr_r_009_nonnumeric_column(self):
        """
        TC-CORR-R-009:
        Non-numeric y column must exit non-zero.
        """
        r = run("jrc_corr_regression.R", data("corr_nonnumeric.csv"))
        assert r.returncode != 0, \
            f"Expected non-zero exit for non-numeric column:\n{combined(r)}"

    def test_tc_corr_r_010_slope_approximately_two(self):
        """
        TC-CORR-R-010:
        For corr_linear.csv (y ≈ 2x + 1), the slope should be approximately 2.0.
        Output must contain "1.9" or "2.0" near the Slope label.
        """
        r = run("jrc_corr_regression.R", data("corr_linear.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Slope" in out, f"Expected 'Slope' in output:\n{out}"
        assert "1.9" in out or "2.0" in out, \
            f"Expected slope ≈ 2.0 (contains '1.9' or '2.0'):\n{out}"

    def test_tc_corr_r_011_bypass_protection(self):
        """
        TC-CORR-R-011:
        Calling jrc_corr_regression.R directly via Rscript without RENV_PATHS_ROOT
        must exit non-zero.
        """
        script = os.path.join(MODULE_ROOT, "R", "jrc_corr_regression.R")
        env = {k: v for k, v in os.environ.items() if k != "RENV_PATHS_ROOT"}
        result = subprocess.run(
            [RSCRIPT_BIN, "--vanilla", script, data("corr_linear.csv")],
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


class TestCorrRegressionNumeric:
    """Numeric correctness assertions — see module docstring for derivations."""

    def test_tc_corr_r_012_slope_exact(self):
        """
        TC-CORR-R-012:
        OLS slope for corr_exact_linear.csv (y=2x+1) = 2.000 ± 0.001.
        Analytical derivation: b1 = Sxy/Sxx = 165/82.5 = 2.000 (exact).
        """
        r = run("jrc_corr_regression.R", data("corr_exact_linear.csv"))
        assert r.returncode == 0, combined(r)
        slope = extract_float(r, "Slope     (b1):")
        print(f"  Slope (b1): extracted = {slope}")
        assert slope is not None, f"Slope not found in output:\n{combined(r)}"
        print(f"  Slope (b1): expected 2.000 ± 0.001, got {slope:.4f}")
        assert abs(slope - 2.000) < 0.001, \
            f"Expected slope = 2.000 ± 0.001, got {slope:.4f}"

    def test_tc_corr_r_013_intercept_exact(self):
        """
        TC-CORR-R-013:
        OLS intercept for corr_exact_linear.csv = 1.000 ± 0.001.
        Analytical derivation: b0 = mean(y) - b1*mean(x) = 12 - 2*5.5 = 1.000 (exact).
        """
        r = run("jrc_corr_regression.R", data("corr_exact_linear.csv"))
        assert r.returncode == 0, combined(r)
        intercept = extract_float(r, "Intercept (b0):")
        print(f"  Intercept (b0): extracted = {intercept}")
        assert intercept is not None, f"Intercept not found in output:\n{combined(r)}"
        print(f"  Intercept (b0): expected 1.000 ± 0.001, got {intercept:.4f}")
        assert abs(intercept - 1.000) < 0.001, \
            f"Expected intercept = 1.000 ± 0.001, got {intercept:.4f}"

    def test_tc_corr_r_014_r_squared_exact(self):
        """
        TC-CORR-R-014:
        R-squared for corr_exact_linear.csv = 1.000 ± 0.001.
        Analytical derivation: r²=1 for perfect linear data (no residuals).
        """
        r = run("jrc_corr_regression.R", data("corr_exact_linear.csv"))
        assert r.returncode == 0, combined(r)
        r2 = extract_float(r, "R-squared:")
        print(f"  R-squared: extracted = {r2}")
        assert r2 is not None, f"R-squared not found in output:\n{combined(r)}"
        print(f"  R-squared: expected 1.000 ± 0.001, got {r2:.4f}")
        assert abs(r2 - 1.000) < 0.001, \
            f"Expected R-squared = 1.000 ± 0.001, got {r2:.4f}"
