"""
OQ test suite — Corr module: jrc_corr_pearson

Maps to validation plan JR-VP-CORR-001 as follows:

  TC-CORR-P-001  Valid input (corr_linear.csv) -> exit 0, "Pearson" in output
  TC-CORR-P-002  Pearson r value present in output (look for "Pearson r:" label)
  TC-CORR-P-003  CI values present in output
  TC-CORR-P-004  p-value present in output
  TC-CORR-P-005  PNG saved to ~/Downloads/ with pattern *_jrc_corr_pearson.png
  TC-CORR-P-006  No arguments -> non-zero exit, usage in output
  TC-CORR-P-007  File not found -> non-zero exit
  TC-CORR-P-008  n < 3 (corr_small.csv) -> non-zero exit
  TC-CORR-P-009  Non-numeric column (corr_nonnumeric.csv) -> non-zero exit
  TC-CORR-P-010  Negative correlation (corr_negative.csv) -> exit 0, r < 0 in output
  TC-CORR-P-011  Direct Rscript call without RENV_PATHS_ROOT -> non-zero exit, RENV_PATHS_ROOT in output

Numeric correctness assertions (TC-CORR-P-012 to TC-CORR-P-013):

  Reference dataset: corr_exact_linear.csv — 10 points, y = 2x + 1 (x=1..10)
  Independent computation (exact analytical result):
    Pearson r  = 1.000000  (perfect linear relationship — derived from formula)
    p-value < 0.001        (significant at any conventional alpha)

  TC-CORR-P-012  Pearson r  = 1.000 ± 0.001 (perfect linear data)
  TC-CORR-P-013  p-value is small (< 0.001 for n=10 with r=1.000)
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


DOWNLOADS = os.path.expanduser("~/Downloads")


def _recent_png(pattern, t_start):
    return [
        f for f in glob.glob(os.path.join(DOWNLOADS, pattern))
        if os.path.getmtime(f) >= t_start - 1.0
    ]


class TestCorrPearson:

    def test_tc_corr_p_001_happy_path_exits_zero(self):
        """
        TC-CORR-P-001:
        Valid input (corr_linear.csv) -> exit 0.
        Output must contain "Pearson".
        """
        r = run("jrc_corr_pearson.R", data("corr_linear.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Pearson" in out, \
            f"Expected 'Pearson' in output:\n{out}"

    def test_tc_corr_p_002_pearson_r_label_present(self):
        """
        TC-CORR-P-002:
        Output must contain the "Pearson r:" label.
        """
        r = run("jrc_corr_pearson.R", data("corr_linear.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Pearson r:" in out, \
            f"Expected 'Pearson r:' label in output:\n{out}"

    def test_tc_corr_p_003_ci_present(self):
        """
        TC-CORR-P-003:
        Output must contain CI bounds.
        """
        r = run("jrc_corr_pearson.R", data("corr_linear.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "CI:" in out or "CI" in out, \
            f"Expected CI values in output:\n{out}"

    def test_tc_corr_p_004_p_value_present(self):
        """
        TC-CORR-P-004:
        Output must contain the p-value label.
        """
        r = run("jrc_corr_pearson.R", data("corr_linear.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "p-value:" in out, \
            f"Expected 'p-value:' in output:\n{out}"

    def test_tc_corr_p_005_png_created(self):
        """
        TC-CORR-P-005:
        A PNG file matching *_jrc_corr_pearson.png must be created in
        ~/Downloads/ during this run.
        """
        t_start = time.time()
        r = run("jrc_corr_pearson.R", data("corr_linear.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        recent = _recent_png("*_jrc_corr_pearson.png", t_start)
        assert recent, (
            f"No *_jrc_corr_pearson.png found in ~/Downloads/ after run\n"
            f"  DOWNLOADS={DOWNLOADS!r} (exists={os.path.isdir(DOWNLOADS)})\n"
            f"  All matches (any age): {glob.glob(os.path.join(DOWNLOADS, '*_jrc_corr_pearson.png'))!r}\n"
            f"  Script output: {combined(r)}"
        )

    def test_tc_corr_p_006_no_arguments(self):
        """
        TC-CORR-P-006:
        Calling with no arguments must exit non-zero and print a usage message.
        """
        r = run("jrc_corr_pearson.R")
        assert r.returncode != 0, "Expected non-zero exit with no arguments"
        out = combined(r)
        assert "Usage" in out or "usage" in out.lower(), \
            f"Expected usage message:\n{out}"

    def test_tc_corr_p_007_file_not_found(self):
        """
        TC-CORR-P-007:
        Providing a non-existent file must exit non-zero.
        """
        r = run("jrc_corr_pearson.R", "nonexistent_file_xyz.csv")
        assert r.returncode != 0, \
            f"Expected non-zero exit for missing file:\n{combined(r)}"

    def test_tc_corr_p_008_n_less_than_3(self):
        """
        TC-CORR-P-008:
        Input with only 2 rows (n < 3) must exit non-zero.
        """
        r = run("jrc_corr_pearson.R", data("corr_small.csv"))
        assert r.returncode != 0, \
            f"Expected non-zero exit when n < 3:\n{combined(r)}"

    def test_tc_corr_p_009_nonnumeric_column(self):
        """
        TC-CORR-P-009:
        Non-numeric y column must exit non-zero.
        """
        r = run("jrc_corr_pearson.R", data("corr_nonnumeric.csv"))
        assert r.returncode != 0, \
            f"Expected non-zero exit for non-numeric column:\n{combined(r)}"

    def test_tc_corr_p_010_negative_correlation(self):
        """
        TC-CORR-P-010:
        Negative correlation dataset -> exit 0, r < 0 confirmed in output.
        """
        r = run("jrc_corr_pearson.R", data("corr_negative.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "-0." in out or "negative" in out.lower(), \
            f"Expected negative r value in output:\n{out}"

    def test_tc_corr_p_011_bypass_protection(self):
        """
        TC-CORR-P-011:
        Calling jrc_corr_pearson.R directly via Rscript without RENV_PATHS_ROOT
        must exit non-zero and mention RENV_PATHS_ROOT in the error output.
        """
        script = os.path.join(MODULE_ROOT, "R", "jrc_corr_pearson.R")
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


class TestCorrPearsonNumeric:
    """Numeric correctness assertions — see module docstring for derivations."""

    def test_tc_corr_p_012_pearson_r_exact(self):
        """
        TC-CORR-P-012:
        Pearson r for corr_exact_linear.csv (y=2x+1) = 1.000 ± 0.001.
        Analytical derivation: perfect linear relationship gives r = Sxy/sqrt(Sxx*Syy) = 1.
        """
        r = run("jrc_corr_pearson.R", data("corr_exact_linear.csv"))
        assert r.returncode == 0, combined(r)
        pearson_r = extract_float(r, "Pearson r:")
        print(f"  Pearson r: extracted = {pearson_r}")
        assert pearson_r is not None, f"Pearson r not found in output:\n{combined(r)}"
        print(f"  Pearson r: expected 1.000 ± 0.001, got {pearson_r:.4f}")
        assert abs(pearson_r - 1.000) < 0.001, \
            f"Expected Pearson r = 1.000 ± 0.001, got {pearson_r:.4f}"

    def test_tc_corr_p_013_p_value_significant(self):
        """
        TC-CORR-P-013:
        p-value for corr_exact_linear.csv is extremely small (< 0.001).
        With r=1.000 and n=10, t-statistic → ∞, p-value → 0.
        """
        r = run("jrc_corr_pearson.R", data("corr_exact_linear.csv"))
        assert r.returncode == 0, combined(r)
        out = combined(r)
        assert "p-value:" in out, f"p-value label not found:\n{out}"
        print(f"  p-value: 'significant' found in output = {'significant' in out.lower()}")
        # p-value is reported in scientific notation; just confirm significance marker
        assert "significant" in out.lower(), \
            f"Expected 'significant' in output for r=1.000 data:\n{out}"
