"""
OQ test suite — SPC module: jrc_spc_imr

Maps to validation plan JR-VP-SPC-001 as follows:

  TC-SPC-IMR-001  Stable dataset → exit 0, key output sections present
  TC-SPC-IMR-002  Stable dataset → IN CONTROL verdict
  TC-SPC-IMR-003  OOC dataset → exit 0, OUT OF CONTROL in output
  TC-SPC-IMR-004  OOC dataset → observation 13 flagged as violation
  TC-SPC-IMR-005  --ucl / --lcl flags accepted, user-specified limits reported
  TC-SPC-IMR-006  PNG written to ~/Downloads/
  TC-SPC-IMR-007  No arguments → non-zero exit, usage message
  TC-SPC-IMR-008  File not found → non-zero exit
  TC-SPC-IMR-009  Missing column → non-zero exit, column name in output
  TC-SPC-IMR-010  Too few observations (1 row) → non-zero exit
  TC-SPC-IMR-011  Bypass protection — direct Rscript call fails
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


class TestIMR:

    def test_tc_spc_imr_001_happy_path_exits_zero(self):
        """
        TC-SPC-IMR-001:
        Stable 25-observation dataset → exit 0.
        Output must contain control limit section, process stability section,
        and a verdict line.
        """
        r = run("jrc_spc_imr.R", data("imr_stable.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Control Limit" in out or "control limit" in out.lower(), \
            "Control limits section missing"
        assert "Stability" in out or "stability" in out.lower() or \
               "IN CONTROL" in out or "OUT OF CONTROL" in out, \
            "Process stability section missing"
        assert "Verdict" in out or "STABLE" in out or "SIGNALS" in out, \
            "Verdict line missing"

    def test_tc_spc_imr_002_stable_data_in_control(self):
        """
        TC-SPC-IMR-002:
        The stable sample dataset is designed to produce no Western Electric
        violations. Output must indicate the process is in control.
        """
        r = run("jrc_spc_imr.R", data("imr_stable.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "IN CONTROL" in out or "STABLE" in out, \
            f"Expected in-control verdict:\n{out}"

    def test_tc_spc_imr_003_ooc_data_exits_zero(self):
        """
        TC-SPC-IMR-003:
        OOC dataset (observation 13 = 11.50, clearly beyond 3σ) → exit 0
        with OUT OF CONTROL in output.
        """
        r = run("jrc_spc_imr.R", data("imr_ooc.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "OUT OF CONTROL" in out or "SIGNALS" in out, \
            f"Expected out-of-control signal:\n{out}"

    def test_tc_spc_imr_004_ooc_observation_flagged(self):
        """
        TC-SPC-IMR-004:
        Observation 13 (value 11.50) must be identified as a Rule 1 violation.
        The output must mention observation 13 in the violations list.
        """
        r = run("jrc_spc_imr.R", data("imr_ooc.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "13" in out, f"Expected observation 13 mentioned in output:\n{out}"
        # Script labels rules as [1], [2], etc. in the violations table
        assert "[1]" in out or "Rule 1" in out or "beyond 3" in out.lower(), \
            f"Expected Rule 1 ([1]) mentioned in violation:\n{out}"

    def test_tc_spc_imr_005_user_limits(self):
        """
        TC-SPC-IMR-005:
        When --ucl and --lcl are provided, output must acknowledge
        user-specified limits and exit 0.
        """
        r = run("jrc_spc_imr.R", data("imr_stable.csv"), "--ucl", "11.0", "--lcl", "9.0")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "user" in out.lower() or "specified" in out.lower() or \
               "11.0" in out or "11.00" in out, \
            f"Expected user-specified UCL mentioned in output:\n{out}"

    def test_tc_spc_imr_006_png_created(self):
        """
        TC-SPC-IMR-006:
        A PNG file matching *_jrc_spc_imr.png must be created in ~/Downloads/
        during this run.
        """
        t_start = time.time()
        r = run("jrc_spc_imr.R", data("imr_stable.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        recent = _recent_png("*_jrc_spc_imr.png", t_start)
        assert recent, "No *_jrc_spc_imr.png found in ~/Downloads/ after run"

    def test_tc_spc_imr_007_no_arguments(self):
        """
        TC-SPC-IMR-007:
        Calling with no arguments must exit non-zero and print a usage message.
        """
        r = run("jrc_spc_imr.R")
        assert r.returncode != 0, "Expected non-zero exit with no arguments"
        out = combined(r)
        assert "Usage" in out or "usage" in out, \
            f"Expected usage message:\n{out}"

    def test_tc_spc_imr_008_file_not_found(self):
        """
        TC-SPC-IMR-008:
        A non-existent CSV path must exit non-zero with an appropriate message.
        """
        r = run("jrc_spc_imr.R", "/tmp/no_such_file_xyz.csv")
        assert r.returncode != 0, "Expected non-zero exit for missing file"
        out = combined(r)
        assert "not found" in out.lower() or "no_such_file" in out, \
            f"Expected 'not found' or filename in output:\n{out}"

    def test_tc_spc_imr_009_missing_column(self):
        """
        TC-SPC-IMR-009:
        A CSV missing the 'value' column must exit non-zero and name the
        missing column in the output.
        """
        r = run("jrc_spc_imr.R", data("imr_missing_col.csv"))
        assert r.returncode != 0, "Expected non-zero exit for missing column"
        out = combined(r)
        assert "value" in out.lower(), \
            f"Expected 'value' mentioned in error:\n{out}"

    def test_tc_spc_imr_010_too_few_observations(self):
        """
        TC-SPC-IMR-010:
        A CSV with only 1 row must exit non-zero (need ≥ 2 for a moving range).
        """
        r = run("jrc_spc_imr.R", data("imr_one_obs.csv"))
        assert r.returncode != 0, "Expected non-zero exit with only 1 observation"

    def test_tc_spc_imr_011_bypass_protection(self):
        """
        TC-SPC-IMR-011:
        Calling jrc_spc_imr.R directly via Rscript without RENV_PATHS_ROOT
        must exit non-zero and mention RENV_PATHS_ROOT in the error output.
        """
        script = os.path.join(MODULE_ROOT, "R", "jrc_spc_imr.R")
        env = {k: v for k, v in os.environ.items() if k != "RENV_PATHS_ROOT"}
        result = subprocess.run(
            ["Rscript", script, data("imr_stable.csv")],
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
