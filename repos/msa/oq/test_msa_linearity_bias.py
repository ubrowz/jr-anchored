"""
OQ test suite — MSA module: jrc_msa_linearity_bias

Maps to validation plan JR-VP-MSA-001 as follows:

  TC-MSA-LB-001  Valid dataset → exit 0, key output sections present
  TC-MSA-LB-002  Known dataset → slope sign and direction correct, significant
  TC-MSA-LB-003  --tolerance flag → %Linearity and %Bias reported, exit 0
  TC-MSA-LB-004  PNG written to ~/Downloads/
  TC-MSA-LB-005  No arguments → non-zero exit, usage message
  TC-MSA-LB-006  File not found → non-zero exit
  TC-MSA-LB-007  Missing 'reference' column → non-zero exit, column named
  TC-MSA-LB-008  Only one part → non-zero exit
  TC-MSA-LB-009  Inconsistent reference values per part → non-zero exit
  TC-MSA-LB-010  Bypass protection — direct Rscript call fails
"""
import sys

# Force UTF-8 stdout/stderr on Windows (cp1252 cannot encode emoji)
if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if sys.stderr.encoding and sys.stderr.encoding.lower() != "utf-8":
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

import glob
import os
import re
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


# ===========================================================================
# OQ tests
# ===========================================================================

class TestLinearityBias:

    def test_tc_msa_lb_001_happy_path_exits_zero(self):
        """
        TC-MSA-LB-001:
        Valid 5-part / 10-replicate dataset → exit 0.
        Output must contain per-part bias table, linearity regression section,
        summary section, and a verdict line.
        """
        r = run("jrc_msa_linearity_bias.R", data("linearity_bias_good.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Per-Part Bias"          in out, "Per-part bias table missing"
        assert "Linearity Regression"   in out, "Linearity regression section missing"
        assert "Summary"                in out, "Summary section missing"
        assert "Verdict"                in out, "Verdict section missing"
        assert "Slope"                  in out, "'Slope' label missing"

    def test_tc_msa_lb_002_known_data_slope_significant(self):
        """
        TC-MSA-LB-002:
        The sample dataset has a positive linearity trend (bias increases with
        reference value). The slope must be positive and its p-value < 0.05.
        """
        r = run("jrc_msa_linearity_bias.R", data("linearity_bias_good.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)

        # Extract slope value
        m_slope = re.search(r"Slope.*?:\s*([-\d.]+)", out)
        assert m_slope, f"Could not parse slope from output:\n{out}"
        slope = float(m_slope.group(1))
        assert slope > 0, f"Expected positive slope for this dataset, got {slope}"

        # Slope p-value should be significant (dataset is designed with clear trend)
        m_p = re.search(r"Slope.*?p\s*=\s*([\d.]+)", out)
        assert m_p, f"Could not parse slope p-value:\n{out}"
        p_val = float(m_p.group(1))
        assert p_val < 0.05, f"Expected slope p < 0.05, got {p_val}"

    def test_tc_msa_lb_003_tolerance_flag(self):
        """
        TC-MSA-LB-003:
        When --tolerance 10.0 is supplied, %Linearity and %Bias must appear
        in the output alongside 'tolerance'. Exit code must be 0.
        """
        r = run("jrc_msa_linearity_bias.R", data("linearity_bias_good.csv"),
                "--tolerance", "10.0")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "tolerance" in out.lower(), \
            f"Expected 'tolerance' in output:\n{out}"
        assert "%Linearity" in out or "Linearity" in out, \
            f"Expected %%Linearity in output:\n{out}"

    def test_tc_msa_lb_004_png_created(self):
        """
        TC-MSA-LB-004:
        A PNG matching *_jrc_msa_linearity_bias.png must be created in
        ~/Downloads/ during this run.
        """
        t_start = time.time()
        r = run("jrc_msa_linearity_bias.R", data("linearity_bias_good.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        recent = _recent_png("*_jrc_msa_linearity_bias.png", t_start)
        assert recent, (
            f"No *_jrc_msa_linearity_bias.png found in ~/Downloads/ after run\n"
            f"  DOWNLOADS={DOWNLOADS!r} (exists={os.path.isdir(DOWNLOADS)})\n"
            f"  All matches (any age): {glob.glob(os.path.join(DOWNLOADS, '*_jrc_msa_linearity_bias.png'))!r}\n"
            f"  Script output: {combined(r)}"
        )

    def test_tc_msa_lb_005_no_arguments(self):
        """
        TC-MSA-LB-005:
        No arguments → non-zero exit, usage message printed.
        """
        r = run("jrc_msa_linearity_bias.R")
        assert r.returncode != 0, "Expected non-zero exit with no arguments"
        assert "Usage" in combined(r) or "usage" in combined(r), \
            f"Expected usage message:\n{combined(r)}"

    def test_tc_msa_lb_006_file_not_found(self):
        """
        TC-MSA-LB-006:
        Non-existent file → non-zero exit, 'not found' in output.
        """
        r = run("jrc_msa_linearity_bias.R", "/tmp/no_such_file_lb.csv")
        assert r.returncode != 0, "Expected non-zero exit for missing file"
        assert "not found" in combined(r).lower(), \
            f"Expected 'not found' in output:\n{combined(r)}"

    def test_tc_msa_lb_007_missing_reference_column(self):
        """
        TC-MSA-LB-007:
        CSV without 'reference' column → non-zero exit, 'reference' named
        in the error message.
        """
        r = run("jrc_msa_linearity_bias.R", data("linearity_bias_missing_col.csv"))
        assert r.returncode != 0, "Expected non-zero exit for missing column"
        assert "reference" in combined(r).lower(), \
            f"Expected 'reference' in error output:\n{combined(r)}"

    def test_tc_msa_lb_008_single_part(self):
        """
        TC-MSA-LB-008:
        Dataset with only one part → non-zero exit. Linearity requires at
        least two reference points to fit a regression.
        """
        r = run("jrc_msa_linearity_bias.R", data("linearity_bias_one_part.csv"))
        assert r.returncode != 0, "Expected non-zero exit with only one part"

    def test_tc_msa_lb_009_inconsistent_reference(self):
        """
        TC-MSA-LB-009:
        A part with multiple different reference values → non-zero exit.
        Each part must have exactly one reference value.
        """
        r = run("jrc_msa_linearity_bias.R",
                data("linearity_bias_inconsistent_ref.csv"))
        assert r.returncode != 0, \
            "Expected non-zero exit for inconsistent reference values"

    def test_tc_msa_lb_010_bypass_protection(self):
        """
        TC-MSA-LB-010:
        Direct Rscript invocation without RENV_PATHS_ROOT → non-zero exit,
        RENV_PATHS_ROOT mentioned in error output.
        """
        script = os.path.join(MODULE_ROOT, "R", "jrc_msa_linearity_bias.R")
        env = {k: v for k, v in os.environ.items() if k != "RENV_PATHS_ROOT"}
        result = subprocess.run(
            [RSCRIPT_BIN, script, data("linearity_bias_good.csv")],
            capture_output=True,
            encoding="utf-8",
            env=env,
            cwd=PROJECT_ROOT,
        )
        assert result.returncode != 0, \
            "Expected non-zero exit when called without RENV_PATHS_ROOT"
        out = (result.stdout or "") + (result.stderr or "")
        assert "RENV_PATHS_ROOT" in out, \
            f"Expected 'RENV_PATHS_ROOT' in error:\n{out}"
