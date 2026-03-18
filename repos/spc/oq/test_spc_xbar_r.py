"""
OQ test suite — SPC module: jrc_spc_xbar_r

Maps to validation plan JR-VP-SPC-001 as follows:

  TC-SPC-XBR-001  Stable dataset → exit 0, key output sections present
  TC-SPC-XBR-002  Stable dataset → IN CONTROL verdict
  TC-SPC-XBR-003  OOC dataset → exit 0, OUT OF CONTROL in output
  TC-SPC-XBR-004  OOC dataset → subgroup sg09 flagged as violation
  TC-SPC-XBR-005  --ucl / --lcl flags accepted, user-specified limits reported
  TC-SPC-XBR-006  PNG written to ~/Downloads/
  TC-SPC-XBR-007  No arguments → non-zero exit, usage message
  TC-SPC-XBR-008  File not found → non-zero exit
  TC-SPC-XBR-009  Missing column → non-zero exit, column name in output
  TC-SPC-XBR-010  Unbalanced subgroups → non-zero exit
  TC-SPC-XBR-011  Subgroup size > 10 → non-zero exit, guidance message
  TC-SPC-XBR-012  Bypass protection — direct Rscript call fails
"""

import glob
import os
import subprocess
import time

from conftest import PROJECT_ROOT, MODULE_ROOT, run, combined, data


DOWNLOADS = os.path.expanduser("~/Downloads")


def _recent_png(pattern, t_start):
    return [
        f for f in glob.glob(os.path.join(DOWNLOADS, pattern))
        if os.path.getmtime(f) >= t_start
    ]


class TestXbarR:

    def test_tc_spc_xbr_001_happy_path_exits_zero(self):
        """
        TC-SPC-XBR-001:
        Stable 20-subgroup / n=5 dataset → exit 0.
        Output must contain X-bar and R chart sections and a verdict.
        """
        r = run("jrc_spc_xbar_r.R", data("xbar_r_stable.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "X-bar" in out or "Xbar" in out or "grand mean" in out.lower() or \
               "Grand Mean" in out, "X-bar section missing"
        assert "Range" in out or "R-bar" in out or "R_bar" in out, \
            "Range section missing"
        assert "Verdict" in out or "IN CONTROL" in out or "OUT OF CONTROL" in out, \
            "Verdict missing"

    def test_tc_spc_xbr_002_stable_data_in_control(self):
        """
        TC-SPC-XBR-002:
        The stable dataset is designed so all subgroup means and ranges fall
        within their control limits. Output must indicate the process is in control.
        """
        r = run("jrc_spc_xbar_r.R", data("xbar_r_stable.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "IN CONTROL" in out or "STABLE" in out, \
            f"Expected in-control verdict:\n{out}"

    def test_tc_spc_xbr_003_ooc_data_exits_zero(self):
        """
        TC-SPC-XBR-003:
        OOC dataset (subgroup sg09 has mean ≈ 53, far above UCL) → exit 0
        with OUT OF CONTROL in output.
        """
        r = run("jrc_spc_xbar_r.R", data("xbar_r_ooc.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "OUT OF CONTROL" in out or "SIGNALS" in out, \
            f"Expected out-of-control signal:\n{out}"

    def test_tc_spc_xbr_004_ooc_subgroup_flagged(self):
        """
        TC-SPC-XBR-004:
        Subgroup sg09 must be identified as a Rule 1 violation in the output.
        """
        r = run("jrc_spc_xbar_r.R", data("xbar_r_ooc.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "sg09" in out, f"Expected 'sg09' in violation output:\n{out}"

    def test_tc_spc_xbr_005_user_limits(self):
        """
        TC-SPC-XBR-005:
        When --ucl and --lcl are provided, output must acknowledge
        user-specified limits and exit 0.
        """
        r = run("jrc_spc_xbar_r.R", data("xbar_r_stable.csv"),
                "--ucl", "52.0", "--lcl", "48.0")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "user" in out.lower() or "specified" in out.lower() or \
               "52.0" in out or "52.00" in out, \
            f"Expected user-specified UCL mentioned in output:\n{out}"

    def test_tc_spc_xbr_006_png_created(self):
        """
        TC-SPC-XBR-006:
        A PNG file matching *_jrc_spc_xbar_r.png must be created in ~/Downloads/
        during this run.
        """
        t_start = time.time()
        r = run("jrc_spc_xbar_r.R", data("xbar_r_stable.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        recent = _recent_png("*_jrc_spc_xbar_r.png", t_start)
        assert recent, "No *_jrc_spc_xbar_r.png found in ~/Downloads/ after run"

    def test_tc_spc_xbr_007_no_arguments(self):
        """
        TC-SPC-XBR-007:
        Calling with no arguments must exit non-zero and print a usage message.
        """
        r = run("jrc_spc_xbar_r.R")
        assert r.returncode != 0, "Expected non-zero exit with no arguments"
        out = combined(r)
        assert "Usage" in out or "usage" in out, \
            f"Expected usage message:\n{out}"

    def test_tc_spc_xbr_008_file_not_found(self):
        """
        TC-SPC-XBR-008:
        A non-existent CSV path must exit non-zero with an appropriate message.
        """
        r = run("jrc_spc_xbar_r.R", "/tmp/no_such_file_xyz.csv")
        assert r.returncode != 0, "Expected non-zero exit for missing file"
        out = combined(r)
        assert "not found" in out.lower() or "no_such_file" in out, \
            f"Expected 'not found' message:\n{out}"

    def test_tc_spc_xbr_009_missing_column(self):
        """
        TC-SPC-XBR-009:
        A CSV missing the 'value' column must exit non-zero and name the
        missing column in the output.
        """
        r = run("jrc_spc_xbar_r.R", data("xbar_r_missing_col.csv"))
        assert r.returncode != 0, "Expected non-zero exit for missing column"
        out = combined(r)
        assert "value" in out.lower(), \
            f"Expected 'value' mentioned in error:\n{out}"

    def test_tc_spc_xbr_010_unbalanced_subgroups(self):
        """
        TC-SPC-XBR-010:
        A dataset with unequal subgroup sizes must exit non-zero and mention
        'unbalanced' or 'equal' in the output.
        """
        r = run("jrc_spc_xbar_r.R", data("xbar_r_unbalanced.csv"))
        assert r.returncode != 0, "Expected non-zero exit for unbalanced subgroups"
        out = combined(r)
        assert any(kw in out.lower() for kw in ("unbalanced", "equal", "same size")), \
            f"Expected unbalanced-design message:\n{out}"

    def test_tc_spc_xbr_011_n_too_large(self):
        """
        TC-SPC-XBR-011:
        A dataset with subgroup size n=11 must exit non-zero. X-bar/R only
        supports n ≤ 10. The output should suggest jrc_spc_xbar_s.
        """
        r = run("jrc_spc_xbar_r.R", data("xbar_r_n_too_large.csv"))
        assert r.returncode != 0, "Expected non-zero exit for n > 10"
        out = combined(r)
        assert "10" in out or "xbar_s" in out.lower() or "xbar_r" in out.lower(), \
            f"Expected size limit message:\n{out}"

    def test_tc_spc_xbr_012_bypass_protection(self):
        """
        TC-SPC-XBR-012:
        Calling jrc_spc_xbar_r.R directly via Rscript without RENV_PATHS_ROOT
        must exit non-zero and mention RENV_PATHS_ROOT in the error output.
        """
        script = os.path.join(MODULE_ROOT, "R", "jrc_spc_xbar_r.R")
        env = {k: v for k, v in os.environ.items() if k != "RENV_PATHS_ROOT"}
        result = subprocess.run(
            ["Rscript", script, data("xbar_r_stable.csv")],
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
