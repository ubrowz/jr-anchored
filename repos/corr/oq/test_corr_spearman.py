"""
OQ test suite — Corr module: jrc_corr_spearman

Maps to validation plan JR-VP-CORR-001 as follows:

  TC-CORR-S-001  Valid input (corr_linear.csv) -> exit 0, "Spearman" in output
  TC-CORR-S-002  Spearman rho value present in output (look for "Spearman rho:" label)
  TC-CORR-S-003  p-value present in output
  TC-CORR-S-004  "Confidence interval" note present in output
  TC-CORR-S-005  PNG saved to ~/Downloads/ with pattern *_jrc_corr_spearman.png
  TC-CORR-S-006  No arguments -> non-zero exit
  TC-CORR-S-007  File not found -> non-zero exit
  TC-CORR-S-008  n < 3 (corr_small.csv) -> non-zero exit
  TC-CORR-S-009  Non-numeric column (corr_nonnumeric.csv) -> non-zero exit
  TC-CORR-S-010  Negative correlation (corr_negative.csv) -> exit 0, rho < 0 in output
  TC-CORR-S-011  Direct Rscript call without RENV_PATHS_ROOT -> non-zero exit
"""

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


class TestCorrSpearman:

    def test_tc_corr_s_001_happy_path_exits_zero(self):
        """
        TC-CORR-S-001:
        Valid input (corr_linear.csv) -> exit 0.
        Output must contain "Spearman".
        """
        r = run("jrc_corr_spearman.R", data("corr_linear.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Spearman" in out, \
            f"Expected 'Spearman' in output:\n{out}"

    def test_tc_corr_s_002_rho_label_present(self):
        """
        TC-CORR-S-002:
        Output must contain the "Spearman rho:" label.
        """
        r = run("jrc_corr_spearman.R", data("corr_linear.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Spearman rho:" in out, \
            f"Expected 'Spearman rho:' label in output:\n{out}"

    def test_tc_corr_s_003_p_value_present(self):
        """
        TC-CORR-S-003:
        Output must contain the p-value label.
        """
        r = run("jrc_corr_spearman.R", data("corr_linear.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "p-value:" in out, \
            f"Expected 'p-value:' in output:\n{out}"

    def test_tc_corr_s_004_ci_note_present(self):
        """
        TC-CORR-S-004:
        Output must contain a note about confidence intervals not being computed.
        """
        r = run("jrc_corr_spearman.R", data("corr_linear.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Confidence interval" in out or "confidence interval" in out.lower(), \
            f"Expected confidence interval note in output:\n{out}"

    def test_tc_corr_s_005_png_created(self):
        """
        TC-CORR-S-005:
        A PNG file matching *_jrc_corr_spearman.png must be created in
        ~/Downloads/ during this run.
        """
        t_start = time.time()
        r = run("jrc_corr_spearman.R", data("corr_linear.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        recent = _recent_png("*_jrc_corr_spearman.png", t_start)
        assert recent, (
            f"No *_jrc_corr_spearman.png found in ~/Downloads/ after run\n"
            f"  DOWNLOADS={DOWNLOADS!r} (exists={os.path.isdir(DOWNLOADS)})\n"
            f"  All matches (any age): {glob.glob(os.path.join(DOWNLOADS, '*_jrc_corr_spearman.png'))!r}\n"
            f"  Script output: {combined(r)}"
        )

    def test_tc_corr_s_006_no_arguments(self):
        """
        TC-CORR-S-006:
        Calling with no arguments must exit non-zero.
        """
        r = run("jrc_corr_spearman.R")
        assert r.returncode != 0, "Expected non-zero exit with no arguments"

    def test_tc_corr_s_007_file_not_found(self):
        """
        TC-CORR-S-007:
        Providing a non-existent file must exit non-zero.
        """
        r = run("jrc_corr_spearman.R", "nonexistent_file_xyz.csv")
        assert r.returncode != 0, \
            f"Expected non-zero exit for missing file:\n{combined(r)}"

    def test_tc_corr_s_008_n_less_than_3(self):
        """
        TC-CORR-S-008:
        Input with only 2 rows (n < 3) must exit non-zero.
        """
        r = run("jrc_corr_spearman.R", data("corr_small.csv"))
        assert r.returncode != 0, \
            f"Expected non-zero exit when n < 3:\n{combined(r)}"

    def test_tc_corr_s_009_nonnumeric_column(self):
        """
        TC-CORR-S-009:
        Non-numeric y column must exit non-zero.
        """
        r = run("jrc_corr_spearman.R", data("corr_nonnumeric.csv"))
        assert r.returncode != 0, \
            f"Expected non-zero exit for non-numeric column:\n{combined(r)}"

    def test_tc_corr_s_010_negative_correlation(self):
        """
        TC-CORR-S-010:
        Negative correlation dataset -> exit 0, rho < 0 confirmed in output.
        """
        r = run("jrc_corr_spearman.R", data("corr_negative.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "-0." in out or "negative" in out.lower(), \
            f"Expected negative rho value in output:\n{out}"

    def test_tc_corr_s_011_bypass_protection(self):
        """
        TC-CORR-S-011:
        Calling jrc_corr_spearman.R directly via Rscript without RENV_PATHS_ROOT
        must exit non-zero.
        """
        script = os.path.join(MODULE_ROOT, "R", "jrc_corr_spearman.R")
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
