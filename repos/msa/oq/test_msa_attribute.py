"""
OQ test suite — MSA module: jrc_msa_attribute

Maps to validation plan JR-VP-MSA-001 as follows:

  TC-MSA-ATT-001  Valid dataset with reference → exit 0, all sections present
  TC-MSA-ATT-002  Valid dataset without reference → exit 0, no vs-reference section
  TC-MSA-ATT-003  Known data — Fleiss' Kappa in expected range, verdicts present
  TC-MSA-ATT-004  Known data with reference — appraiser A is perfect (Kappa = 1.0)
  TC-MSA-ATT-005  PNG written to ~/Downloads/
  TC-MSA-ATT-006  No arguments → non-zero exit, usage message
  TC-MSA-ATT-007  File not found → non-zero exit
  TC-MSA-ATT-008  Missing 'trial' column → non-zero exit, column named
  TC-MSA-ATT-009  Only one appraiser → non-zero exit
  TC-MSA-ATT-010  Unbalanced design → non-zero exit
  TC-MSA-ATT-011  Bypass protection — direct Rscript call fails
"""

import glob
import os
import re
import subprocess
import time

from conftest import PROJECT_ROOT, MODULE_ROOT, run, combined, data


DOWNLOADS = os.path.expanduser("~/Downloads")


def _recent_png(pattern, t_start):
    return [
        f for f in glob.glob(os.path.join(DOWNLOADS, pattern))
        if os.path.getmtime(f) >= t_start
    ]


class TestAttribute:

    def test_tc_msa_att_001_with_reference_exits_zero(self):
        """
        TC-MSA-ATT-001:
        Dataset with reference column → exit 0. All four sections must be
        present: Within-Appraiser, Between-Appraiser, Vs Reference, Verdict.
        """
        r = run("jrc_msa_attribute.R", data("attribute_with_ref.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Within-Appraiser"  in out, "Within-appraiser section missing"
        assert "Between-Appraiser" in out, "Between-appraiser section missing"
        assert "vs Reference" in out or "Vs Reference" in out or "Appraiser vs" in out, \
            "Vs-reference section missing"
        assert "Verdict"           in out, "Verdict section missing"
        assert "Fleiss"            in out, "Fleiss Kappa missing"

    def test_tc_msa_att_002_without_reference_exits_zero(self):
        """
        TC-MSA-ATT-002:
        Dataset without reference column → exit 0. Vs-reference section must
        NOT appear.
        """
        r = run("jrc_msa_attribute.R", data("attribute_no_ref.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Within-Appraiser"  in out
        assert "Between-Appraiser" in out
        assert "Vs Reference"      not in out, \
            "Vs-reference section should not appear without reference column"

    def test_tc_msa_att_003_fleiss_kappa_range(self):
        """
        TC-MSA-ATT-003:
        Known sample dataset → Fleiss' Kappa must be between 0.7 and 1.0
        and verdict must be MARGINAL or ACCEPTABLE.
        """
        r = run("jrc_msa_attribute.R", data("attribute_with_ref.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)

        m = re.search(r"Fleiss[''].*?Kappa.*?:\s*([-\d.]+)", out)
        assert m, f"Could not parse Fleiss Kappa:\n{out}"
        kappa = float(m.group(1))
        assert 0.7 <= kappa <= 1.0, f"Expected Fleiss Kappa in [0.7, 1.0], got {kappa}"
        assert any(v in out for v in ("MARGINAL", "ACCEPTABLE")), \
            "Expected MARGINAL or ACCEPTABLE verdict"

    def test_tc_msa_att_004_perfect_appraiser_vs_reference(self):
        """
        TC-MSA-ATT-004:
        In the sample data, appraiser A never disagrees with the reference.
        Their Kappa vs reference must be 1.0000.
        """
        r = run("jrc_msa_attribute.R", data("attribute_with_ref.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)

        # Find "Vs Ref:  A" line in the verdict section
        m = re.search(r"Vs Ref\s+A\s+Kappa\s*=\s*([\d.]+)", out)
        assert m, f"Could not find Vs Ref A kappa in verdict:\n{out}"
        assert float(m.group(1)) == 1.0, \
            f"Expected Kappa = 1.0 for appraiser A vs reference, got {m.group(1)}"

    def test_tc_msa_att_005_png_created(self):
        """TC-MSA-ATT-005: PNG matching *_jrc_msa_attribute.png created in ~/Downloads/."""
        t_start = time.time()
        r = run("jrc_msa_attribute.R", data("attribute_with_ref.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        assert _recent_png("*_jrc_msa_attribute.png", t_start), \
            "No *_jrc_msa_attribute.png in ~/Downloads/"

    def test_tc_msa_att_006_no_arguments(self):
        """TC-MSA-ATT-006: No arguments → non-zero exit, usage message."""
        r = run("jrc_msa_attribute.R")
        assert r.returncode != 0
        assert "Usage" in combined(r) or "usage" in combined(r)

    def test_tc_msa_att_007_file_not_found(self):
        """TC-MSA-ATT-007: Non-existent file → non-zero exit."""
        r = run("jrc_msa_attribute.R", "/tmp/no_such_attr.csv")
        assert r.returncode != 0
        assert "not found" in combined(r).lower()

    def test_tc_msa_att_008_missing_trial_column(self):
        """TC-MSA-ATT-008: Missing 'trial' column → non-zero exit, 'trial' named."""
        r = run("jrc_msa_attribute.R", data("attribute_missing_col.csv"))
        assert r.returncode != 0
        assert "trial" in combined(r).lower()

    def test_tc_msa_att_009_single_appraiser(self):
        """TC-MSA-ATT-009: Only one appraiser → non-zero exit."""
        r = run("jrc_msa_attribute.R", data("attribute_one_appraiser.csv"))
        assert r.returncode != 0

    def test_tc_msa_att_010_unbalanced_design(self):
        """TC-MSA-ATT-010: Unbalanced design → non-zero exit."""
        r = run("jrc_msa_attribute.R", data("attribute_unbalanced.csv"))
        assert r.returncode != 0
        assert any(kw in combined(r).lower()
                   for kw in ("unbalanced", "trials", "equal"))

    def test_tc_msa_att_011_bypass_protection(self):
        """TC-MSA-ATT-011: Direct Rscript call without RENV_PATHS_ROOT → non-zero exit."""
        script = os.path.join(MODULE_ROOT, "R", "jrc_msa_attribute.R")
        env = {k: v for k, v in os.environ.items() if k != "RENV_PATHS_ROOT"}
        result = subprocess.run(
            ["Rscript", script, data("attribute_with_ref.csv")],
            capture_output=True, text=True, env=env, cwd=PROJECT_ROOT,
        )
        assert result.returncode != 0
        assert "RENV_PATHS_ROOT" in result.stdout + result.stderr
