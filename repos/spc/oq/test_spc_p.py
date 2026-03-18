"""
OQ test suite — SPC module: jrc_spc_p

Maps to validation plan JR-VP-SPC-001 as follows:

  TC-SPC-P-001  Stable dataset → exit 0, key output sections present
  TC-SPC-P-002  Stable dataset → IN CONTROL verdict
  TC-SPC-P-003  Known p_bar computed correctly (≈ 0.041)
  TC-SPC-P-004  OOC dataset → exit 0, OUT OF CONTROL in output
  TC-SPC-P-005  OOC dataset → subgroup 13 flagged as violation
  TC-SPC-P-006  PNG written to ~/Downloads/
  TC-SPC-P-007  No arguments → non-zero exit, usage message
  TC-SPC-P-008  File not found → non-zero exit
  TC-SPC-P-009  Missing column → non-zero exit, column name in output
  TC-SPC-P-010  defectives > n → non-zero exit
  TC-SPC-P-011  Bypass protection — direct Rscript call fails
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


class TestPChart:

    def test_tc_spc_p_001_happy_path_exits_zero(self):
        """
        TC-SPC-P-001:
        Stable 25-subgroup dataset → exit 0.
        Output must contain p-bar, control limits, and a verdict.
        """
        r = run("jrc_spc_p.R", data("p_stable.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "p-bar" in out.lower() or "p_bar" in out.lower() or \
               "proportion" in out.lower(), "p-bar section missing"
        assert "UCL" in out or "Control Limit" in out or "control limit" in out.lower(), \
            "Control limits section missing"
        assert "Verdict" in out or "IN CONTROL" in out or "OUT OF CONTROL" in out, \
            "Verdict missing"

    def test_tc_spc_p_002_stable_data_in_control(self):
        """
        TC-SPC-P-002:
        The stable dataset (max proportion = 0.06, UCL ≈ 0.10) → IN CONTROL.
        """
        r = run("jrc_spc_p.R", data("p_stable.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "IN CONTROL" in out or "STABLE" in out, \
            f"Expected in-control verdict:\n{out}"

    def test_tc_spc_p_003_known_p_bar(self):
        """
        TC-SPC-P-003:
        With 103 total defectives across 2500 inspected, p_bar = 0.0412.
        The output must report a p-bar value close to 0.041.
        """
        r = run("jrc_spc_p.R", data("p_stable.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        # Accept any representation near 0.041: 0.041, 0.0412, 4.1%, 4.12%
        assert re.search(r"0\.04[01234]|4\.[01234]%", out), \
            f"Expected p_bar near 0.041 in output:\n{out}"

    def test_tc_spc_p_004_ooc_data_exits_zero(self):
        """
        TC-SPC-P-004:
        OOC dataset (subgroup 13 = 15/100 = 0.15, above UCL ≈ 0.10) → exit 0
        with OUT OF CONTROL in output.
        """
        r = run("jrc_spc_p.R", data("p_ooc.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "OUT OF CONTROL" in out or "SIGNALS" in out, \
            f"Expected out-of-control signal:\n{out}"

    def test_tc_spc_p_005_ooc_subgroup_flagged(self):
        """
        TC-SPC-P-005:
        Subgroup 13 must be identified as a violation in the output.
        """
        r = run("jrc_spc_p.R", data("p_ooc.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "13" in out, f"Expected subgroup 13 in violation output:\n{out}"

    def test_tc_spc_p_006_png_created(self):
        """
        TC-SPC-P-006:
        A PNG file matching *_jrc_spc_p.png must be created in ~/Downloads/.
        """
        t_start = time.time()
        r = run("jrc_spc_p.R", data("p_stable.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        recent = _recent_png("*_jrc_spc_p.png", t_start)
        assert recent, "No *_jrc_spc_p.png found in ~/Downloads/ after run"

    def test_tc_spc_p_007_no_arguments(self):
        """
        TC-SPC-P-007:
        Calling with no arguments must exit non-zero and print a usage message.
        """
        r = run("jrc_spc_p.R")
        assert r.returncode != 0, "Expected non-zero exit with no arguments"
        out = combined(r)
        assert "Usage" in out or "usage" in out, \
            f"Expected usage message:\n{out}"

    def test_tc_spc_p_008_file_not_found(self):
        """
        TC-SPC-P-008:
        A non-existent CSV path must exit non-zero with an appropriate message.
        """
        r = run("jrc_spc_p.R", "/tmp/no_such_file_xyz.csv")
        assert r.returncode != 0, "Expected non-zero exit for missing file"
        out = combined(r)
        assert "not found" in out.lower() or "no_such_file" in out, \
            f"Expected 'not found' message:\n{out}"

    def test_tc_spc_p_009_missing_column(self):
        """
        TC-SPC-P-009:
        A CSV missing the 'defectives' column must exit non-zero and name the
        missing column in the output.
        """
        r = run("jrc_spc_p.R", data("p_missing_col.csv"))
        assert r.returncode != 0, "Expected non-zero exit for missing column"
        out = combined(r)
        assert "defective" in out.lower(), \
            f"Expected 'defective' mentioned in error:\n{out}"

    def test_tc_spc_p_010_defectives_exceed_n(self):
        """
        TC-SPC-P-010:
        A row where defectives > n (101 > 100) must exit non-zero with an
        appropriate validation message.
        """
        r = run("jrc_spc_p.R", data("p_invalid.csv"))
        assert r.returncode != 0, "Expected non-zero exit when defectives > n"
        out = combined(r)
        assert any(kw in out.lower() for kw in
                   ("defective", "exceed", "greater", "cannot", "invalid")), \
            f"Expected validation error message:\n{out}"

    def test_tc_spc_p_011_bypass_protection(self):
        """
        TC-SPC-P-011:
        Calling jrc_spc_p.R directly via Rscript without RENV_PATHS_ROOT
        must exit non-zero and mention RENV_PATHS_ROOT in the error output.
        """
        script = os.path.join(MODULE_ROOT, "R", "jrc_spc_p.R")
        env = {k: v for k, v in os.environ.items() if k != "RENV_PATHS_ROOT"}
        result = subprocess.run(
            ["Rscript", script, data("p_stable.csv")],
            capture_output=True,
            text=True,
            env=env,
            cwd=PROJECT_ROOT,
        )
        assert result.returncode != 0, \
            "Expected non-zero exit when called without RENV_PATHS_ROOT"
        out = result.stdout + result.stderr
        assert "RENV_PATHS_ROOT" in out, \
            f"Expected 'RENV_PATHS_ROOT' in error output:\n{out}"
