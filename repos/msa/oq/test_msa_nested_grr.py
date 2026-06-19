"""
OQ test suite — MSA module: jrc_msa_nested_grr

Maps to validation plan JR-VP-MSA-001 as follows:

  TC-MSA-NGR-001  Balanced nested dataset → exit 0, all sections present
  TC-MSA-NGR-002  Known good data → %GRR in expected range, verdict ACCEPTABLE
  TC-MSA-NGR-003  Known poor data → verdict UNACCEPTABLE
  TC-MSA-NGR-004  --tolerance flag → %GRR vs tolerance reported, exit 0
  TC-MSA-NGR-005  PNG written to ~/Downloads/
  TC-MSA-NGR-006  No arguments → non-zero exit, usage message
  TC-MSA-NGR-007  File not found → non-zero exit
  TC-MSA-NGR-008  Missing 'replicate' column → non-zero exit, column named
  TC-MSA-NGR-009  Only one operator → non-zero exit
  TC-MSA-NGR-010  Unbalanced design (operators have different part counts) → non-zero exit
  TC-MSA-NGR-011  Bypass protection — direct Rscript call fails
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


DOWNLOADS = os.path.expanduser("~/Downloads")


def _recent_png(pattern, t_start):
    return [
        f for f in glob.glob(os.path.join(DOWNLOADS, pattern))
        if os.path.getmtime(f) >= t_start - 1.0
    ]


class TestNestedGRR:

    def test_tc_msa_ngr_001_happy_path_exits_zero(self):
        """
        TC-MSA-NGR-001:
        Balanced 5-part / 3-operator / 2-replicate nested dataset → exit 0.
        Output must contain ANOVA table, variance components, study variation,
        and a verdict line.
        """
        r = run("jrc_msa_nested_grr.R", data("nested_grr_good.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "ANOVA" in out,               "ANOVA table header missing"
        assert "Variance Components" in out, "Variance components section missing"
        assert "Study Variation" in out,     "Study variation section missing"
        assert "Verdict" in out,             "Verdict section missing"
        assert "Gauge R&R" in out,           "'Gauge R&R' label missing"
        assert "Nested" in out,              "'Nested' indicator missing"

    def test_tc_msa_ngr_002_known_good_data_acceptable(self):
        """
        TC-MSA-NGR-002:
        Known low-noise dataset → %GRR < 30% and verdict must be ACCEPTABLE or MARGINAL.
        """
        r = run("jrc_msa_nested_grr.R", data("nested_grr_good.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)

        m = re.search(r"%GRR.*?Study Var.*?:\s*([\d.]+)%", out)
        if not m:
            m = re.search(r"Gauge R&R\s+[\d.]+\s+([\d.]+)%", out)
        if not m:
            m = re.search(r"%GRR.*?:\s*([\d.]+)%", out)
        assert m, f"Could not parse %GRR from output:\n{out}"
        pct_grr = float(m.group(1))
        assert pct_grr < 30, f"Expected %GRR < 30%, got {pct_grr}"
        assert any(v in out for v in ("ACCEPTABLE", "MARGINAL")), \
            "Expected ACCEPTABLE or MARGINAL verdict"

    def test_tc_msa_ngr_003_known_poor_data_unacceptable(self):
        """
        TC-MSA-NGR-003:
        Dataset with very high within-operator variability → verdict UNACCEPTABLE.
        """
        r = run("jrc_msa_nested_grr.R", data("nested_grr_poor.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "UNACCEPTABLE" in out, \
            f"Expected UNACCEPTABLE verdict for high-noise data:\n{out}"

    def test_tc_msa_ngr_004_tolerance_flag(self):
        """
        TC-MSA-NGR-004:
        --tolerance flag → %GRR vs tolerance section appears, exit 0.
        """
        r = run("jrc_msa_nested_grr.R", data("nested_grr_good.csv"), "--tolerance", "10.0")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Tolerance" in out or "tolerance" in out, \
            "Expected tolerance-referenced output when --tolerance supplied"
        assert re.search(r"\d+\.\d+%", out), "Expected a percentage value in output"

    def test_tc_msa_ngr_005_png_created(self):
        """TC-MSA-NGR-005: PNG matching *_jrc_msa_nested_grr.png created in ~/Downloads/."""
        t_start = time.time()
        r = run("jrc_msa_nested_grr.R", data("nested_grr_good.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        recent_ngr = _recent_png("*_jrc_msa_nested_grr.png", t_start)
        assert recent_ngr, (
            f"No *_jrc_msa_nested_grr.png in ~/Downloads/\n"
            f"  DOWNLOADS={DOWNLOADS!r} (exists={os.path.isdir(DOWNLOADS)})\n"
            f"  All matches (any age): {glob.glob(os.path.join(DOWNLOADS, '*_jrc_msa_nested_grr.png'))!r}\n"
            f"  Script output: {combined(r)}"
        )

    def test_tc_msa_ngr_006_no_arguments(self):
        """TC-MSA-NGR-006: No arguments → non-zero exit, usage message."""
        r = run("jrc_msa_nested_grr.R")
        assert r.returncode != 0
        assert "Usage" in combined(r) or "usage" in combined(r)

    def test_tc_msa_ngr_007_file_not_found(self):
        """TC-MSA-NGR-007: Non-existent file → non-zero exit."""
        r = run("jrc_msa_nested_grr.R", "/tmp/no_such_nested.csv")
        assert r.returncode != 0
        assert "not found" in combined(r).lower()

    def test_tc_msa_ngr_008_missing_replicate_column(self):
        """TC-MSA-NGR-008: Missing 'replicate' column → non-zero exit, 'replicate' named."""
        r = run("jrc_msa_nested_grr.R", data("nested_grr_missing_col.csv"))
        assert r.returncode != 0
        assert "replicate" in combined(r).lower()

    def test_tc_msa_ngr_009_single_operator(self):
        """TC-MSA-NGR-009: Only one operator → non-zero exit."""
        r = run("jrc_msa_nested_grr.R", data("nested_grr_one_operator.csv"))
        assert r.returncode != 0

    def test_tc_msa_ngr_010_unbalanced_design(self):
        """
        TC-MSA-NGR-010:
        Operators have different numbers of parts → non-zero exit,
        'unbalanced' or 'parts' in error message.
        """
        r = run("jrc_msa_nested_grr.R", data("nested_grr_unbalanced.csv"))
        assert r.returncode != 0
        out = combined(r).lower()
        assert any(kw in out for kw in ("unbalanced", "parts", "equal")), \
            f"Expected unbalanced-design error:\n{combined(r)}"

    def test_tc_msa_ngr_011_bypass_protection(self):
        """TC-MSA-NGR-012: Direct Rscript call without RENV_PATHS_ROOT → non-zero exit."""
        script = os.path.join(MODULE_ROOT, "R", "jrc_msa_nested_grr.R")
        env = {k: v for k, v in os.environ.items() if k != "RENV_PATHS_ROOT"}
        result = subprocess.run(
            [RSCRIPT_BIN, script, data("nested_grr_good.csv")],
            capture_output=True, encoding="utf-8", env=env, cwd=PROJECT_ROOT,
        )
        assert result.returncode != 0
        assert "RENV_PATHS_ROOT" in (result.stdout or "") + (result.stderr or "")
