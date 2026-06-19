"""
OQ test suite — MSA module: jrc_msa_type1

Maps to validation plan JR-VP-MSA-001 as follows:

  TC-MSA-T1-001  Valid dataset → exit 0, key output sections present
  TC-MSA-T1-002  Known good data → Cg and Cgk are acceptable (>= 1.33)
  TC-MSA-T1-003  Biased dataset → bias significant, Cgk < Cg
  TC-MSA-T1-004  PNG written to ~/Downloads/
  TC-MSA-T1-005  No arguments → non-zero exit, usage message
  TC-MSA-T1-006  Missing --reference → non-zero exit
  TC-MSA-T1-007  Missing --tolerance → non-zero exit
  TC-MSA-T1-008  File not found → non-zero exit
  TC-MSA-T1-009  Missing 'value' column → non-zero exit, 'value' named
  TC-MSA-T1-010  Fewer than 10 measurements → non-zero exit
  TC-MSA-T1-011  Bypass protection — direct Rscript call fails

Numeric correctness assertions (TC-MSA-T1-012 to TC-MSA-T1-013):

  Reference dataset: type1_good.csv (n=25, reference=10.0, tolerance=0.5)
  Independent computation using ISO 22514-7 / AIAG formulas:
    SD   = 0.00267 (sample SD via n-1)
    bias = 0.00988 (mean - reference)
    Cg   = 0.2 * T / (6 * SD) = 6.250
    Cgk  = min(0.1*T - bias, 0.1*T + bias) / (3 * SD) = 5.015

  TC-MSA-T1-012  Cg  = 6.250 ± 0.005
  TC-MSA-T1-013  Cgk = 5.015 ± 0.005
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

from conftest import PROJECT_ROOT, MODULE_ROOT, run, combined, data, extract_float, RSCRIPT_BIN


DOWNLOADS = os.path.expanduser("~/Downloads")


def _recent_png(pattern, t_start):
    return [
        f for f in glob.glob(os.path.join(DOWNLOADS, pattern))
        if os.path.getmtime(f) >= t_start - 1.0
    ]


# ===========================================================================
# OQ tests
# ===========================================================================

class TestType1:

    def test_tc_msa_t1_001_happy_path_exits_zero(self):
        """
        TC-MSA-T1-001:
        Valid 25-measurement dataset → exit 0.
        Output must contain descriptive statistics, gauge capability section,
        %Var/%Bias, and verdict.
        """
        r = run("jrc_msa_type1.R", data("type1_good.csv"),
                "--reference", "10.000", "--tolerance", "0.5")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Descriptive Statistics" in out, "Descriptive statistics section missing"
        assert "Gauge Capability"       in out, "Gauge capability section missing"
        assert "Cg"                     in out, "'Cg' missing"
        assert "Cgk"                    in out, "'Cgk' missing"
        assert "Verdict"                in out, "Verdict section missing"

    def test_tc_msa_t1_002_known_good_data_acceptable(self):
        """
        TC-MSA-T1-002:
        Sample dataset has SD ~ 0.003 against tolerance 0.5 → Cg >> 1.33.
        Both Cg and Cgk must be >= 1.33 and verdict must be ACCEPTABLE.
        """
        r = run("jrc_msa_type1.R", data("type1_good.csv"),
                "--reference", "10.000", "--tolerance", "0.5")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)

        m_cg  = re.search(r"Cg\s*[:=]\s*([\d.]+)", out)
        m_cgk = re.search(r"Cgk\s*[:=]\s*([\d.]+)", out)
        assert m_cg,  f"Could not parse Cg from output:\n{out}"
        assert m_cgk, f"Could not parse Cgk from output:\n{out}"

        assert float(m_cg.group(1))  >= 1.33, f"Expected Cg >= 1.33"
        assert float(m_cgk.group(1)) >= 1.33, f"Expected Cgk >= 1.33"
        assert "ACCEPTABLE" in out

    def test_tc_msa_t1_003_biased_data_cgk_lower_than_cg(self):
        """
        TC-MSA-T1-003:
        Dataset with bias of ~0.1 relative to reference 10.0, tolerance 0.5.
        Bias should be flagged as significant and Cgk must be lower than Cg.
        """
        r = run("jrc_msa_type1.R", data("type1_biased.csv"),
                "--reference", "10.000", "--tolerance", "0.5")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)

        m_cg  = re.search(r"Cg\s*[:=]\s*(-?[\d.]+)", out)
        m_cgk = re.search(r"Cgk\s*[:=]\s*(-?[\d.]+)", out)
        assert m_cg and m_cgk, f"Could not parse Cg/Cgk:\n{out}"
        assert float(m_cgk.group(1)) < float(m_cg.group(1)), \
            "Expected Cgk < Cg when gauge is biased"
        assert "significant" in out.lower() or "*" in out, \
            "Expected bias significance flag in output"

    def test_tc_msa_t1_004_png_created(self):
        """
        TC-MSA-T1-004:
        A PNG matching *_jrc_msa_type1.png must be created in ~/Downloads/.
        """
        t_start = time.time()
        r = run("jrc_msa_type1.R", data("type1_good.csv"),
                "--reference", "10.000", "--tolerance", "0.5")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        recent_t1 = _recent_png("*_jrc_msa_type1.png", t_start)
        assert recent_t1, (
            f"No *_jrc_msa_type1.png found in ~/Downloads/\n"
            f"  DOWNLOADS={DOWNLOADS!r} (exists={os.path.isdir(DOWNLOADS)})\n"
            f"  All matches (any age): {glob.glob(os.path.join(DOWNLOADS, '*_jrc_msa_type1.png'))!r}\n"
            f"  Script output: {combined(r)}"
        )

    def test_tc_msa_t1_005_no_arguments(self):
        """TC-MSA-T1-005: No arguments → non-zero exit, usage message."""
        r = run("jrc_msa_type1.R")
        assert r.returncode != 0
        assert "Usage" in combined(r) or "usage" in combined(r)

    def test_tc_msa_t1_006_missing_reference(self):
        """TC-MSA-T1-006: --reference not supplied → non-zero exit."""
        r = run("jrc_msa_type1.R", data("type1_good.csv"),
                "--tolerance", "0.5")
        assert r.returncode != 0, "Expected non-zero exit without --reference"
        assert "reference" in combined(r).lower()

    def test_tc_msa_t1_007_missing_tolerance(self):
        """TC-MSA-T1-007: --tolerance not supplied → non-zero exit."""
        r = run("jrc_msa_type1.R", data("type1_good.csv"),
                "--reference", "10.000")
        assert r.returncode != 0, "Expected non-zero exit without --tolerance"
        assert "tolerance" in combined(r).lower()

    def test_tc_msa_t1_008_file_not_found(self):
        """TC-MSA-T1-008: Non-existent file → non-zero exit."""
        r = run("jrc_msa_type1.R", "/tmp/no_such_type1.csv",
                "--reference", "10.0", "--tolerance", "0.5")
        assert r.returncode != 0
        assert "not found" in combined(r).lower()

    def test_tc_msa_t1_009_missing_value_column(self):
        """TC-MSA-T1-009: CSV without 'value' column → non-zero exit, 'value' named."""
        r = run("jrc_msa_type1.R", data("type1_missing_value_col.csv"),
                "--reference", "10.0", "--tolerance", "0.5")
        assert r.returncode != 0
        assert "value" in combined(r).lower()

    def test_tc_msa_t1_010_too_few_measurements(self):
        """TC-MSA-T1-010: Fewer than 10 measurements → non-zero exit."""
        r = run("jrc_msa_type1.R", data("type1_too_few.csv"),
                "--reference", "10.0", "--tolerance", "0.5")
        assert r.returncode != 0

    def test_tc_msa_t1_011_bypass_protection(self):
        """
        TC-MSA-T1-011:
        Direct Rscript call without RENV_PATHS_ROOT → non-zero exit,
        RENV_PATHS_ROOT in error output.
        """
        script = os.path.join(MODULE_ROOT, "R", "jrc_msa_type1.R")
        env = {k: v for k, v in os.environ.items() if k != "RENV_PATHS_ROOT"}
        result = subprocess.run(
            [RSCRIPT_BIN, script, data("type1_good.csv"),
             "--reference", "10.0", "--tolerance", "0.5"],
            capture_output=True, encoding="utf-8", env=env, cwd=PROJECT_ROOT,
        )
        assert result.returncode != 0
        assert "RENV_PATHS_ROOT" in (result.stdout or "") + (result.stderr or "")


class TestMsaType1Numeric:
    """Numeric correctness assertions — see module docstring for derivations."""

    def test_tc_msa_t1_012_cg_exact(self):
        """
        TC-MSA-T1-012:
        Cg for type1_good.csv = 6.250 ± 0.005.
        Independent reference: Cg = 0.2 * T / (6 * SD) = 0.1 / 0.01602 = 6.250.
        """
        r = run("jrc_msa_type1.R", data("type1_good.csv"),
                "--reference", "10.0", "--tolerance", "0.5")
        assert r.returncode == 0, combined(r)
        m = re.search(r"\bCg\s*[:=]\s*([\d.]+)", combined(r))
        assert m, f"Cg not found in output:\n{combined(r)}"
        cg = float(m.group(1))
        print(f"  Cg: expected 6.250 ± 0.005, got {cg:.3f}")
        assert abs(cg - 6.250) < 0.005, \
            f"Expected Cg = 6.250 ± 0.005, got {cg:.3f}"

    def test_tc_msa_t1_013_cgk_exact(self):
        """
        TC-MSA-T1-013:
        Cgk for type1_good.csv = 5.015 ± 0.005.
        Independent reference: Cgk = (0.1*T - bias) / (3*SD) = 0.04012/0.00801 = 5.015.
        """
        r = run("jrc_msa_type1.R", data("type1_good.csv"),
                "--reference", "10.0", "--tolerance", "0.5")
        assert r.returncode == 0, combined(r)
        m = re.search(r"\bCgk\s*[:=]\s*([\d.]+)", combined(r))
        assert m, f"Cgk not found in output:\n{combined(r)}"
        cgk = float(m.group(1))
        print(f"  Cgk: expected 5.015 ± 0.005, got {cgk:.3f}")
        assert abs(cgk - 5.015) < 0.005, \
            f"Expected Cgk = 5.015 ± 0.005, got {cgk:.3f}"
