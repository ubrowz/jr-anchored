"""
OQ test suite — AS module: jrc_as_evaluate

Maps to validation plan JR-VP-AS-001 as follows:

  TC-AS-EVAL-001  attr_accept_lot.csv --type attributes --c 2 -> ACCEPT
  TC-AS-EVAL-002  attr_reject_lot.csv --type attributes --c 2 -> REJECT
  TC-AS-EVAL-003  var_accept_lot.csv --type variables --k 1.45 --lsl 9.5 -> ACCEPT
  TC-AS-EVAL-004  var_reject_lot.csv --type variables --k 1.45 --lsl 9.5 -> REJECT
  TC-AS-EVAL-005  Variables mode PNG written to ~/Downloads/
  TC-AS-EVAL-006  Attributes mode PNG written to ~/Downloads/
  TC-AS-EVAL-007  Missing --type -> non-zero exit
  TC-AS-EVAL-008  Attributes mode missing --c -> non-zero exit
  TC-AS-EVAL-009  Variables mode missing --k -> non-zero exit
  TC-AS-EVAL-010  Attributes mode: attr_missing_result.csv -> non-zero exit, 'result' in error
  TC-AS-EVAL-011  Variables mode: var_missing_value.csv -> non-zero exit, 'value' in error
  TC-AS-EVAL-012  Bypass protection
"""

import glob
import os
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


class TestEvaluate:

    def test_tc_as_eval_001_attributes_accept(self):
        """
        TC-AS-EVAL-001:
        attr_accept_lot.csv has 1 defective. With --c 2 the verdict must be ACCEPT.
        """
        r = run("jrc_as_evaluate.R", data("attr_accept_lot.csv"),
                "--type", "attributes", "--c", "2")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "ACCEPT" in out, f"Expected ACCEPT verdict:\n{out}"

    def test_tc_as_eval_002_attributes_reject(self):
        """
        TC-AS-EVAL-002:
        attr_reject_lot.csv has 5 defectives. With --c 2 the verdict must be REJECT.
        """
        r = run("jrc_as_evaluate.R", data("attr_reject_lot.csv"),
                "--type", "attributes", "--c", "2")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "REJECT" in out, f"Expected REJECT verdict:\n{out}"

    def test_tc_as_eval_003_variables_accept(self):
        """
        TC-AS-EVAL-003:
        var_accept_lot.csv: mean ~10.45, sd ~0.051. With --lsl 9.5 --k 1.45,
        Q_L = (10.45 - 9.5) / 0.051 >> 1.45, so verdict must be ACCEPT.
        """
        r = run("jrc_as_evaluate.R", data("var_accept_lot.csv"),
                "--type", "variables", "--k", "1.45", "--lsl", "9.5")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "ACCEPT" in out, f"Expected ACCEPT verdict:\n{out}"

    def test_tc_as_eval_004_variables_reject(self):
        """
        TC-AS-EVAL-004:
        var_reject_lot.csv: mean=9.6, sd=0.102. With --lsl 9.5 --k 1.45,
        Q_L = (9.6 - 9.5) / 0.102 = 0.98 < 1.45, so verdict must be REJECT.
        """
        r = run("jrc_as_evaluate.R", data("var_reject_lot.csv"),
                "--type", "variables", "--k", "1.45", "--lsl", "9.5")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "REJECT" in out, f"Expected REJECT verdict:\n{out}"

    def test_tc_as_eval_005_variables_png_created(self):
        """
        TC-AS-EVAL-005:
        Variables mode must write a PNG matching *_jrc_as_evaluate.png to ~/Downloads/.
        """
        t_start = time.time()
        r = run("jrc_as_evaluate.R", data("var_accept_lot.csv"),
                "--type", "variables", "--k", "1.45", "--lsl", "9.5")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        recent = _recent_png("*_jrc_as_evaluate.png", t_start)
        assert recent, (
            f"No *_jrc_as_evaluate.png found in ~/Downloads/ after variables run\n"
            f"  DOWNLOADS={DOWNLOADS!r} (exists={os.path.isdir(DOWNLOADS)})\n"
            f"  All matches (any age): {glob.glob(os.path.join(DOWNLOADS, '*_jrc_as_evaluate.png'))!r}\n"
            f"  Script output: {combined(r)}"
        )

    def test_tc_as_eval_006_attributes_png_created(self):
        """
        TC-AS-EVAL-006:
        Attributes mode must write a PNG matching *_jrc_as_evaluate.png to ~/Downloads/.
        """
        t_start = time.time()
        r = run("jrc_as_evaluate.R", data("attr_accept_lot.csv"),
                "--type", "attributes", "--c", "2")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        recent = _recent_png("*_jrc_as_evaluate.png", t_start)
        assert recent, (
            f"No *_jrc_as_evaluate.png found in ~/Downloads/ after attributes run\n"
            f"  DOWNLOADS={DOWNLOADS!r} (exists={os.path.isdir(DOWNLOADS)})\n"
            f"  All matches (any age): {glob.glob(os.path.join(DOWNLOADS, '*_jrc_as_evaluate.png'))!r}\n"
            f"  Script output: {combined(r)}"
        )

    def test_tc_as_eval_007_missing_type(self):
        """
        TC-AS-EVAL-007:
        Omitting --type must exit non-zero.
        """
        r = run("jrc_as_evaluate.R", data("attr_accept_lot.csv"), "--c", "2")
        assert r.returncode != 0, \
            f"Expected non-zero exit when --type is missing:\n{combined(r)}"

    def test_tc_as_eval_008_attributes_missing_c(self):
        """
        TC-AS-EVAL-008:
        Attributes mode without --c must exit non-zero.
        """
        r = run("jrc_as_evaluate.R", data("attr_accept_lot.csv"),
                "--type", "attributes")
        assert r.returncode != 0, \
            f"Expected non-zero exit when --c is missing:\n{combined(r)}"

    def test_tc_as_eval_009_variables_missing_k(self):
        """
        TC-AS-EVAL-009:
        Variables mode without --k must exit non-zero.
        """
        r = run("jrc_as_evaluate.R", data("var_accept_lot.csv"),
                "--type", "variables", "--lsl", "9.5")
        assert r.returncode != 0, \
            f"Expected non-zero exit when --k is missing:\n{combined(r)}"

    def test_tc_as_eval_010_attributes_missing_result_column(self):
        """
        TC-AS-EVAL-010:
        attr_missing_result.csv has no 'result' column -> non-zero exit,
        'result' must appear in the error output.
        """
        r = run("jrc_as_evaluate.R", data("attr_missing_result.csv"),
                "--type", "attributes", "--c", "2")
        assert r.returncode != 0, \
            f"Expected non-zero exit for missing result column:\n{combined(r)}"
        out = combined(r)
        assert "result" in out.lower(), \
            f"Expected 'result' mentioned in error:\n{out}"

    def test_tc_as_eval_011_variables_missing_value_column(self):
        """
        TC-AS-EVAL-011:
        var_missing_value.csv has no 'value' column -> non-zero exit,
        'value' must appear in the error output.
        """
        r = run("jrc_as_evaluate.R", data("var_missing_value.csv"),
                "--type", "variables", "--k", "1.45", "--lsl", "9.5")
        assert r.returncode != 0, \
            f"Expected non-zero exit for missing value column:\n{combined(r)}"
        out = combined(r)
        assert "value" in out.lower(), \
            f"Expected 'value' mentioned in error:\n{out}"

    def test_tc_as_eval_012_bypass_protection(self):
        """
        TC-AS-EVAL-012:
        Calling jrc_as_evaluate.R directly via Rscript without RENV_PATHS_ROOT
        must exit non-zero and mention RENV_PATHS_ROOT in the error output.
        """
        script = os.path.join(MODULE_ROOT, "R", "jrc_as_evaluate.R")
        env = {k: v for k, v in os.environ.items() if k != "RENV_PATHS_ROOT"}
        result = subprocess.run(
            [RSCRIPT_BIN, script, data("attr_accept_lot.csv"),
             "--type", "attributes", "--c", "2"],
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
