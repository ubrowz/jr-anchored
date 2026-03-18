"""
OQ test suite — SPC module: jrc_spc_c

Maps to validation plan JR-VP-SPC-001 as follows:

  TC-SPC-C-001  Stable dataset → exit 0, key output sections present
  TC-SPC-C-002  Stable dataset → IN CONTROL verdict
  TC-SPC-C-003  Known c_bar computed correctly (≈ 4.88)
  TC-SPC-C-004  OOC dataset → exit 0, OUT OF CONTROL in output
  TC-SPC-C-005  OOC dataset → subgroup 12 flagged as violation
  TC-SPC-C-006  PNG written to ~/Downloads/
  TC-SPC-C-007  No arguments → non-zero exit, usage message
  TC-SPC-C-008  File not found → non-zero exit
  TC-SPC-C-009  Missing column → non-zero exit, column name in output
  TC-SPC-C-010  Bypass protection — direct Rscript call fails
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


class TestCChart:

    def test_tc_spc_c_001_happy_path_exits_zero(self):
        """
        TC-SPC-C-001:
        Stable 25-subgroup dataset → exit 0.
        Output must contain c-bar, control limits, and a verdict.
        """
        r = run("jrc_spc_c.R", data("c_stable.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "c-bar" in out.lower() or "c_bar" in out.lower() or \
               "mean defect" in out.lower() or "defects per" in out.lower(), \
            "c-bar section missing"
        assert "UCL" in out or "Control Limit" in out or "control limit" in out.lower(), \
            "Control limits section missing"
        assert "Verdict" in out or "IN CONTROL" in out or "OUT OF CONTROL" in out, \
            "Verdict missing"

    def test_tc_spc_c_002_stable_data_in_control(self):
        """
        TC-SPC-C-002:
        The stable dataset (max defects = 7, UCL ≈ 11.5) → IN CONTROL.
        """
        r = run("jrc_spc_c.R", data("c_stable.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "IN CONTROL" in out or "STABLE" in out, \
            f"Expected in-control verdict:\n{out}"

    def test_tc_spc_c_003_known_c_bar(self):
        """
        TC-SPC-C-003:
        With 122 total defects across 25 subgroups, c_bar = 4.88.
        The output must report a c-bar value close to 4.88.
        """
        r = run("jrc_spc_c.R", data("c_stable.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert re.search(r"4\.8[0-9]|4\.9[0-9]", out), \
            f"Expected c_bar near 4.88 in output:\n{out}"

    def test_tc_spc_c_004_ooc_data_exits_zero(self):
        """
        TC-SPC-C-004:
        OOC dataset (subgroup 12 = 15 defects, above UCL ≈ 11.5) → exit 0
        with OUT OF CONTROL in output.
        """
        r = run("jrc_spc_c.R", data("c_ooc.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "OUT OF CONTROL" in out or "SIGNALS" in out, \
            f"Expected out-of-control signal:\n{out}"

    def test_tc_spc_c_005_ooc_subgroup_flagged(self):
        """
        TC-SPC-C-005:
        Subgroup 12 must be identified as a violation in the output.
        """
        r = run("jrc_spc_c.R", data("c_ooc.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "12" in out, f"Expected subgroup 12 in violation output:\n{out}"

    def test_tc_spc_c_006_png_created(self):
        """
        TC-SPC-C-006:
        A PNG file matching *_jrc_spc_c.png must be created in ~/Downloads/.
        """
        t_start = time.time()
        r = run("jrc_spc_c.R", data("c_stable.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        recent = _recent_png("*_jrc_spc_c.png", t_start)
        assert recent, "No *_jrc_spc_c.png found in ~/Downloads/ after run"

    def test_tc_spc_c_007_no_arguments(self):
        """
        TC-SPC-C-007:
        Calling with no arguments must exit non-zero and print a usage message.
        """
        r = run("jrc_spc_c.R")
        assert r.returncode != 0, "Expected non-zero exit with no arguments"
        out = combined(r)
        assert "Usage" in out or "usage" in out, \
            f"Expected usage message:\n{out}"

    def test_tc_spc_c_008_file_not_found(self):
        """
        TC-SPC-C-008:
        A non-existent CSV path must exit non-zero with an appropriate message.
        """
        r = run("jrc_spc_c.R", "/tmp/no_such_file_xyz.csv")
        assert r.returncode != 0, "Expected non-zero exit for missing file"
        out = combined(r)
        assert "not found" in out.lower() or "no_such_file" in out, \
            f"Expected 'not found' message:\n{out}"

    def test_tc_spc_c_009_missing_column(self):
        """
        TC-SPC-C-009:
        A CSV missing the 'defects' column must exit non-zero and name the
        missing column in the output.
        """
        r = run("jrc_spc_c.R", data("c_missing_col.csv"))
        assert r.returncode != 0, "Expected non-zero exit for missing column"
        out = combined(r)
        assert "defect" in out.lower(), \
            f"Expected 'defect' mentioned in error:\n{out}"

    def test_tc_spc_c_010_bypass_protection(self):
        """
        TC-SPC-C-010:
        Calling jrc_spc_c.R directly via Rscript without RENV_PATHS_ROOT
        must exit non-zero and mention RENV_PATHS_ROOT in the error output.
        """
        script = os.path.join(MODULE_ROOT, "R", "jrc_spc_c.R")
        env = {k: v for k, v in os.environ.items() if k != "RENV_PATHS_ROOT"}
        result = subprocess.run(
            ["Rscript", script, data("c_stable.csv")],
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
