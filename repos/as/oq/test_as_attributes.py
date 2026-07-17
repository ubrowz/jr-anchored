"""
OQ test suite — AS module: jrc_as_attributes

Maps to validation plan JR-VP-AS-001 as follows:

  TC-AS-ATTR-001  Valid inputs -> exit 0, Single Sampling section in output
  TC-AS-ATTR-002  Single plan has n and c present in output
  TC-AS-ATTR-003  Double sampling plan section present in output
  TC-AS-ATTR-004  OC curve table present (p and Pa columns)
  TC-AS-ATTR-005  PNG written to ~/Downloads/ with pattern *_jrc_as_attributes.png
  TC-AS-ATTR-006  No arguments -> non-zero exit, usage in output
  TC-AS-ATTR-007  aql >= rql -> non-zero exit
  TC-AS-ATTR-008  aql > 1 -> non-zero exit
  TC-AS-ATTR-009  lot_size = 1 -> non-zero exit
  TC-AS-ATTR-010  --alpha > 1 -> non-zero exit
  TC-AS-ATTR-011  Direct Rscript call without RENV_PATHS_ROOT -> non-zero exit + RENV_PATHS_ROOT in output

Numeric correctness assertions (TC-AS-ATTR-012 to TC-AS-ATTR-013):

  Reference: N=500, AQL=0.01, RQL=0.10 → single plan: n=51, c=2
  Independent computation using hypergeometric CDF (ISO 2859-1 / ASTM E2234):
    Pa(p=0.01) = P(X≤2 | Hypergeom(N=500, K=5, n=51))  = 0.9913
    Pa(p=0.10) = P(X≤2 | Hypergeom(N=500, K=50, n=51)) = 0.0918

  Pa values read from the OC Curve table in the output.

  TC-AS-ATTR-012  Pa at p=0.010 (AQL) = 0.9913 ± 0.0005
  TC-AS-ATTR-013  Pa at p=0.100 (RQL) = 0.0918 ± 0.0005
"""
import sys

# Force UTF-8 stdout/stderr on Windows (cp1252 cannot encode emoji)
if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if sys.stderr.encoding and sys.stderr.encoding.lower() != "utf-8":
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

import glob
import os
import subprocess
import time

import re

from conftest import PROJECT_ROOT, MODULE_ROOT, run, combined, data, extract_float, RSCRIPT_BIN


# Where the script under test writes its artifacts. The OQ runner sets
# JR_OUT_DIR to this run's own folder; the default matches the scripts'
# own default, so a suite run by hand still looks in ~/Downloads.
DOWNLOADS = os.environ.get("JR_OUT_DIR") or os.path.expanduser("~/Downloads")


def _recent_png(pattern, t_start):
    return [
        f for f in glob.glob(os.path.join(DOWNLOADS, pattern))
        if os.path.getmtime(f) >= t_start - 1.0
    ]


class TestAttributes:

    def test_tc_as_attr_001_happy_path_exits_zero(self):
        """
        TC-AS-ATTR-001:
        Valid inputs (N=500, AQL=0.01, RQL=0.10) -> exit 0.
        Output must contain a Single Sampling section.
        """
        r = run("jrc_as_attributes.R", "500", "0.01", "0.10")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Single Sampling" in out or "Single sampling" in out.lower(), \
            f"Expected 'Single Sampling' section in output:\n{out}"

    def test_tc_as_attr_002_single_plan_n_and_c_present(self):
        """
        TC-AS-ATTR-002:
        Single plan output must contain both sample size (n) and
        acceptance number (c) labelled values.
        """
        r = run("jrc_as_attributes.R", "500", "0.01", "0.10")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Sample size" in out or "n)" in out or "n =" in out or "(n)" in out, \
            f"Expected sample size (n) in output:\n{out}"
        assert "Acceptance number" in out or "c)" in out or "(c)" in out, \
            f"Expected acceptance number (c) in output:\n{out}"

    def test_tc_as_attr_003_double_plan_section_present(self):
        """
        TC-AS-ATTR-003:
        Output must contain a Double Sampling section.
        """
        r = run("jrc_as_attributes.R", "500", "0.01", "0.10")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Double Sampling" in out or "Double sampling" in out.lower() or \
               "Stage 1" in out or "n1" in out, \
            f"Expected double sampling section in output:\n{out}"

    def test_tc_as_attr_004_oc_curve_table_present(self):
        """
        TC-AS-ATTR-004:
        Output must include an OC Curve table with p and Pa columns.
        """
        r = run("jrc_as_attributes.R", "500", "0.01", "0.10")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "OC Curve" in out or "OC curve" in out.lower(), \
            f"Expected OC Curve section:\n{out}"
        assert "Pa" in out, f"Expected 'Pa' column header in OC table:\n{out}"

    def test_tc_as_attr_005_png_created(self):
        """
        TC-AS-ATTR-005:
        A PNG file matching *_jrc_as_attributes.png must be created in
        ~/Downloads/ during this run.
        """
        t_start = time.time()
        r = run("jrc_as_attributes.R", "500", "0.01", "0.10")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        recent = _recent_png("*_jrc_as_attributes.png", t_start)
        assert recent, (
            f"No *_jrc_as_attributes.png found in ~/Downloads/ after run\n"
            f"  DOWNLOADS={DOWNLOADS!r} (exists={os.path.isdir(DOWNLOADS)})\n"
            f"  All matches (any age): {glob.glob(os.path.join(DOWNLOADS, '*_jrc_as_attributes.png'))!r}\n"
            f"  Script output: {combined(r)}"
        )

    def test_tc_as_attr_006_no_arguments(self):
        """
        TC-AS-ATTR-006:
        Calling with no arguments must exit non-zero and print a usage message.
        """
        r = run("jrc_as_attributes.R")
        assert r.returncode != 0, "Expected non-zero exit with no arguments"
        out = combined(r)
        assert "Usage" in out or "usage" in out.lower(), \
            f"Expected usage message:\n{out}"

    def test_tc_as_attr_007_aql_gte_rql(self):
        """
        TC-AS-ATTR-007:
        Providing aql >= rql must exit non-zero.
        """
        r = run("jrc_as_attributes.R", "500", "0.10", "0.01")
        assert r.returncode != 0, \
            f"Expected non-zero exit when aql >= rql:\n{combined(r)}"

    def test_tc_as_attr_008_aql_greater_than_one(self):
        """
        TC-AS-ATTR-008:
        Providing aql > 1 must exit non-zero.
        """
        r = run("jrc_as_attributes.R", "500", "1.5", "0.10")
        assert r.returncode != 0, \
            f"Expected non-zero exit when aql > 1:\n{combined(r)}"

    def test_tc_as_attr_009_lot_size_one(self):
        """
        TC-AS-ATTR-009:
        lot_size = 1 must exit non-zero (minimum is 2).
        """
        r = run("jrc_as_attributes.R", "1", "0.01", "0.10")
        assert r.returncode != 0, \
            f"Expected non-zero exit when lot_size = 1:\n{combined(r)}"

    def test_tc_as_attr_010_alpha_out_of_range(self):
        """
        TC-AS-ATTR-010:
        --alpha > 1 must exit non-zero.
        """
        r = run("jrc_as_attributes.R", "500", "0.01", "0.10", "--alpha", "1.5")
        assert r.returncode != 0, \
            f"Expected non-zero exit when --alpha > 1:\n{combined(r)}"

    def test_tc_as_attr_011_bypass_protection(self):
        """
        TC-AS-ATTR-011:
        Calling jrc_as_attributes.R directly via Rscript without RENV_PATHS_ROOT
        must exit non-zero and mention RENV_PATHS_ROOT in the error output.
        """
        script = os.path.join(MODULE_ROOT, "R", "jrc_as_attributes.R")
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


class TestAsAttributesNumeric:
    """Numeric correctness assertions — see module docstring for derivations."""

    def test_tc_as_attr_012_pa_at_aql_exact(self):
        """
        TC-AS-ATTR-012:
        Pa at p=0.010 (AQL) for N=500, n=51, c=2 plan = 0.9913 ± 0.0005.
        Independent reference: Hypergeometric CDF P(X≤2 | N=500, K=5, n=51) = 0.9913.
        """
        r = run("jrc_as_attributes.R", "500", "0.01", "0.10")
        assert r.returncode == 0, combined(r)
        # Extract Pa for p=0.010 from OC Curve table row "  0.010   0.XXXX"
        m = re.search(r"0\.010\s+([\d.]+)", combined(r))
        assert m, f"Pa at p=0.010 not found in OC table:\n{combined(r)}"
        pa = float(m.group(1))
        print(f"  Pa(AQL): expected 0.9913 ± 0.0005, got {pa:.4f}")
        assert abs(pa - 0.9913) < 0.0005, \
            f"Expected Pa(AQL) = 0.9913 ± 0.0005, got {pa:.4f}"

    def test_tc_as_attr_013_pa_at_rql_exact(self):
        """
        TC-AS-ATTR-013:
        Pa at p=0.100 (RQL) for N=500, n=51, c=2 plan = 0.0918 ± 0.0005.
        Independent reference: Hypergeometric CDF P(X≤2 | N=500, K=50, n=51) = 0.0918.
        """
        r = run("jrc_as_attributes.R", "500", "0.01", "0.10")
        assert r.returncode == 0, combined(r)
        # Extract Pa for p=0.100 from OC Curve table row "  0.100   0.XXXX"
        m = re.search(r"0\.100\s+([\d.]+)", combined(r))
        assert m, f"Pa at p=0.100 not found in OC table:\n{combined(r)}"
        pa = float(m.group(1))
        print(f"  Pa(RQL): expected 0.0918 ± 0.0005, got {pa:.4f}")
        assert abs(pa - 0.0918) < 0.0005, \
            f"Expected Pa(RQL) = 0.0918 ± 0.0005, got {pa:.4f}"
