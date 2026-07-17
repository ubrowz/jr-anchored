"""
OQ test suite — AS module: jrc_as_oc_curve

Maps to validation plan JR-VP-AS-001 as follows:

  TC-AS-OCC-001  Valid n=32, c=1 -> exit 0, Pa values in output
  TC-AS-OCC-002  Pa at p=0.001 is > 0.99 in output
  TC-AS-OCC-003  Pa decreases as p increases (check first and last Pa rows)
  TC-AS-OCC-004  --lot-size flag accepted without error
  TC-AS-OCC-005  PNG written to ~/Downloads/ with pattern *_jrc_as_oc_curve.png
  TC-AS-OCC-006  --aql and --rql accepted without error and 'AQL' appears in output
  TC-AS-OCC-007  No arguments -> non-zero exit
  TC-AS-OCC-008  c >= n -> non-zero exit
  TC-AS-OCC-009  n <= 0 -> non-zero exit
  TC-AS-OCC-010  Bypass protection
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


class TestOCCurve:

    def test_tc_as_occ_001_happy_path_exits_zero(self):
        """
        TC-AS-OCC-001:
        Valid inputs n=32, c=1 -> exit 0. Output must contain Pa values.
        """
        r = run("jrc_as_oc_curve.R", "32", "1")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Pa" in out, f"Expected Pa column in output:\n{out}"

    def test_tc_as_occ_002_pa_near_one_at_low_p(self):
        """
        TC-AS-OCC-002:
        Pa at p=0.001 must be > 0.99 for n=32, c=1.
        The output table should show a value >= 0.99 in the first data row.
        """
        r = run("jrc_as_oc_curve.R", "32", "1")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        # Extract all 4-decimal floats — first after the header should be near 1.0
        values = re.findall(r"\b(0\.\d{4}|1\.0000)\b", out)
        if values:
            first_pa = float(values[0])
            assert first_pa > 0.99, \
                f"Expected first Pa > 0.99, got {first_pa}"

    def test_tc_as_occ_003_pa_decreases(self):
        """
        TC-AS-OCC-003:
        Pa values must decrease as p increases.
        Check that the first Pa in the table is greater than the last.
        """
        r = run("jrc_as_oc_curve.R", "32", "1")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        # Extract rows like "0.005  0.9988  0.0012"
        rows = re.findall(r"^\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)", out, re.MULTILINE)
        if len(rows) >= 2:
            first_pa = float(rows[0][1])
            last_pa  = float(rows[-1][1])
            assert first_pa > last_pa, \
                f"Expected Pa to decrease: first={first_pa}, last={last_pa}"

    def test_tc_as_occ_004_lot_size_flag(self):
        """
        TC-AS-OCC-004:
        --lot-size flag must be accepted without error.
        """
        r = run("jrc_as_oc_curve.R", "32", "1", "--lot-size", "500")
        assert r.returncode == 0, \
            f"Expected exit 0 with --lot-size:\n{combined(r)}"

    def test_tc_as_occ_005_png_created(self):
        """
        TC-AS-OCC-005:
        A PNG matching *_jrc_as_oc_curve.png must be created in ~/Downloads/.
        """
        t_start = time.time()
        r = run("jrc_as_oc_curve.R", "32", "1")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        recent = _recent_png("*_jrc_as_oc_curve.png", t_start)
        assert recent, (
            f"No *_jrc_as_oc_curve.png found in ~/Downloads/ after run\n"
            f"  DOWNLOADS={DOWNLOADS!r} (exists={os.path.isdir(DOWNLOADS)})\n"
            f"  All matches (any age): {glob.glob(os.path.join(DOWNLOADS, '*_jrc_as_oc_curve.png'))!r}\n"
            f"  Script output: {combined(r)}"
        )

    def test_tc_as_occ_006_aql_rql_flags(self):
        """
        TC-AS-OCC-006:
        --aql and --rql flags must be accepted without error and 'AQL' must
        appear in the output.
        """
        r = run("jrc_as_oc_curve.R", "32", "1", "--aql", "0.01", "--rql", "0.10")
        assert r.returncode == 0, \
            f"Expected exit 0 with --aql and --rql:\n{combined(r)}"
        out = combined(r)
        assert "AQL" in out, f"Expected 'AQL' in output:\n{out}"

    def test_tc_as_occ_007_no_arguments(self):
        """
        TC-AS-OCC-007:
        Calling with no arguments must exit non-zero.
        """
        r = run("jrc_as_oc_curve.R")
        assert r.returncode != 0, "Expected non-zero exit with no arguments"

    def test_tc_as_occ_008_c_gte_n(self):
        """
        TC-AS-OCC-008:
        c >= n must exit non-zero.
        """
        r = run("jrc_as_oc_curve.R", "32", "32")
        assert r.returncode != 0, \
            f"Expected non-zero exit when c >= n:\n{combined(r)}"

    def test_tc_as_occ_009_n_zero_or_negative(self):
        """
        TC-AS-OCC-009:
        n <= 0 must exit non-zero.
        """
        r = run("jrc_as_oc_curve.R", "0", "0")
        assert r.returncode != 0, \
            f"Expected non-zero exit when n=0:\n{combined(r)}"

    def test_tc_as_occ_010_bypass_protection(self):
        """
        TC-AS-OCC-010:
        Calling jrc_as_oc_curve.R directly via Rscript without RENV_PATHS_ROOT
        must exit non-zero and mention RENV_PATHS_ROOT in the error output.
        """
        script = os.path.join(MODULE_ROOT, "R", "jrc_as_oc_curve.R")
        env = {k: v for k, v in os.environ.items() if k != "RENV_PATHS_ROOT"}
        result = subprocess.run(
            [RSCRIPT_BIN, script, "32", "1"],
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
