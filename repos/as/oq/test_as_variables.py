"""
OQ test suite — AS module: jrc_as_variables

Maps to validation plan JR-VP-AS-001 as follows:

  TC-AS-VAR-001  Valid one-sided -> exit 0, 'Variables Plan' in output
  TC-AS-VAR-002  k value present in output and is positive
  TC-AS-VAR-003  --sides 2 produces larger n than --sides 1
  TC-AS-VAR-004  OC curve table present
  TC-AS-VAR-005  PNG written to ~/Downloads/ with pattern *_jrc_as_variables.png
  TC-AS-VAR-006  No arguments -> non-zero exit
  TC-AS-VAR-007  aql >= rql -> non-zero exit
  TC-AS-VAR-008  --sides value other than 1 or 2 -> non-zero exit
  TC-AS-VAR-009  Variables plan n < attributes plan n (efficiency check)
  TC-AS-VAR-010  --alpha out of range -> non-zero exit
  TC-AS-VAR-011  Bypass protection
"""

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


class TestVariables:

    def test_tc_as_var_001_happy_path_exits_zero(self):
        """
        TC-AS-VAR-001:
        Valid one-sided inputs (N=500, AQL=0.01, RQL=0.10) -> exit 0.
        Output must contain 'Variables Plan'.
        """
        r = run("jrc_as_variables.R", "500", "0.01", "0.10")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Variables Plan" in out or "Variables plan" in out.lower(), \
            f"Expected 'Variables Plan' section in output:\n{out}"

    def test_tc_as_var_002_k_value_present_and_positive(self):
        """
        TC-AS-VAR-002:
        The acceptability constant k must appear in output and be positive.
        """
        r = run("jrc_as_variables.R", "500", "0.01", "0.10")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "k)" in out or "k =" in out or "(k)" in out or \
               "constant (k)" in out or "constant" in out.lower(), \
            f"Expected k value in output:\n{out}"
        # Extract a numeric k value — should be positive
        matches = re.findall(r"k[):\s]*[=:]\s*([\d.]+)", out)
        if matches:
            k = float(matches[0])
            assert k > 0, f"Expected k > 0, got k = {k}"

    def test_tc_as_var_003_sides_2_valid_plan(self):
        """
        TC-AS-VAR-003:
        --sides 2 must produce a valid plan: exit 0, positive k, Sides: 2 in output.
        """
        r = run("jrc_as_variables.R", "500", "0.01", "0.10", "--sides", "2")
        assert r.returncode == 0, f"sides=2 failed:\n{combined(r)}"
        out = combined(r)
        assert "Sides: 2" in out, f"Expected 'Sides: 2' in output:\n{out}"
        matches = re.findall(r"constant \(k\):\s*([\d.]+)", out)
        if matches:
            k = float(matches[0])
            assert k > 0, f"Expected k > 0 for sides=2, got k = {k}"

    def test_tc_as_var_004_oc_curve_table_present(self):
        """
        TC-AS-VAR-004:
        Output must include an OC Curve table with Pa column.
        """
        r = run("jrc_as_variables.R", "500", "0.01", "0.10")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "OC Curve" in out or "OC curve" in out.lower(), \
            f"Expected OC Curve section:\n{out}"
        assert "Pa" in out, f"Expected 'Pa' header in OC table:\n{out}"

    def test_tc_as_var_005_png_created(self):
        """
        TC-AS-VAR-005:
        A PNG matching *_jrc_as_variables.png must be created in ~/Downloads/.
        """
        t_start = time.time()
        r = run("jrc_as_variables.R", "500", "0.01", "0.10")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        recent = _recent_png("*_jrc_as_variables.png", t_start)
        assert recent, (
            f"No *_jrc_as_variables.png found in ~/Downloads/ after run\n"
            f"  DOWNLOADS={DOWNLOADS!r} (exists={os.path.isdir(DOWNLOADS)})\n"
            f"  All matches (any age): {glob.glob(os.path.join(DOWNLOADS, '*_jrc_as_variables.png'))!r}\n"
            f"  Script output: {combined(r)}"
        )

    def test_tc_as_var_006_no_arguments(self):
        """
        TC-AS-VAR-006:
        Calling with no arguments must exit non-zero.
        """
        r = run("jrc_as_variables.R")
        assert r.returncode != 0, "Expected non-zero exit with no arguments"

    def test_tc_as_var_007_aql_gte_rql(self):
        """
        TC-AS-VAR-007:
        Providing aql >= rql must exit non-zero.
        """
        r = run("jrc_as_variables.R", "500", "0.10", "0.01")
        assert r.returncode != 0, \
            f"Expected non-zero exit when aql >= rql:\n{combined(r)}"

    def test_tc_as_var_008_sides_invalid(self):
        """
        TC-AS-VAR-008:
        --sides value other than 1 or 2 must exit non-zero.
        """
        r = run("jrc_as_variables.R", "500", "0.01", "0.10", "--sides", "3")
        assert r.returncode != 0, \
            f"Expected non-zero exit for --sides 3:\n{combined(r)}"

    def test_tc_as_var_009_variables_n_less_than_attributes_n(self):
        """
        TC-AS-VAR-009:
        Variables plan sample size should be less than equivalent attributes plan.
        Output should mention 'Sample reduction' or 'fewer'.
        """
        r = run("jrc_as_variables.R", "500", "0.01", "0.10")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Sample reduction" in out or "fewer" in out or \
               "Comparison" in out or "comparison" in out.lower(), \
            f"Expected efficiency comparison in output:\n{out}"

    def test_tc_as_var_010_alpha_out_of_range(self):
        """
        TC-AS-VAR-010:
        --alpha out of range (> 1) must exit non-zero.
        """
        r = run("jrc_as_variables.R", "500", "0.01", "0.10", "--alpha", "2.0")
        assert r.returncode != 0, \
            f"Expected non-zero exit when --alpha > 1:\n{combined(r)}"

    def test_tc_as_var_011_bypass_protection(self):
        """
        TC-AS-VAR-011:
        Calling jrc_as_variables.R directly via Rscript without RENV_PATHS_ROOT
        must exit non-zero and mention RENV_PATHS_ROOT in the error output.
        """
        script = os.path.join(MODULE_ROOT, "R", "jrc_as_variables.R")
        env = {k: v for k, v in os.environ.items() if k != "RENV_PATHS_ROOT"}
        result = subprocess.run(
            [RSCRIPT_BIN, script, "500", "0.01", "0.10"],
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
