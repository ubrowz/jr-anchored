"""
OQ test suite — SPC module: jrc_spc_xbar_s

Maps to validation plan JR-VP-SPC-001 as follows:

  TC-SPC-XBS-001  Stable dataset → exit 0, key output sections present
  TC-SPC-XBS-002  Stable dataset → IN CONTROL verdict
  TC-SPC-XBS-003  OOC dataset → exit 0, OUT OF CONTROL in output
  TC-SPC-XBS-004  OOC dataset → subgroup sg09 flagged as violation
  TC-SPC-XBS-005  --ucl / --lcl flags accepted, user-specified limits reported
  TC-SPC-XBS-006  PNG written to ~/Downloads/
  TC-SPC-XBS-007  No arguments → non-zero exit, usage message
  TC-SPC-XBS-008  File not found → non-zero exit
  TC-SPC-XBS-009  Missing column → non-zero exit, column name in output
  TC-SPC-XBS-010  Unbalanced subgroups → non-zero exit
  TC-SPC-XBS-011  Bypass protection — direct Rscript call fails

Numeric correctness assertions (TC-SPC-XBS-012 to TC-SPC-XBS-015):

  Reference dataset: xbar_s_stable.csv (20 subgroups × 8 measurements)
  Independent computation using Shewhart X-bar & S formulas:
    grand X-bar = 100.060000
    s-bar       = 0.473726
    c4(n=8)     = 0.965030,  A3 = 3/(c4*sqrt(8)) = 1.099095
    B4(n=8)     = 1.814910
    UCL_x = X-bar + A3*s-bar = 100.060 + 1.099095*0.473726 = 100.5807
    LCL_x = X-bar - A3*s-bar = 100.060 - 1.099095*0.473726 = 99.5393
    UCL_s = B4 * s-bar        = 1.814910 * 0.473726         = 0.8598

  TC-SPC-XBS-012  Grand X-bar = 100.060  ± 0.001
  TC-SPC-XBS-013  UCL (X-bar) = 100.5807 ± 0.001
  TC-SPC-XBS-014  LCL (X-bar) = 99.5393  ± 0.001
  TC-SPC-XBS-015  UCL_s       = 0.8598   ± 0.001

--report sidecar assertions (TC-SPC-XBS-016 to TC-SPC-XBS-018):

  TC-SPC-XBS-016  --report → exit 0, HTML report written to ~/Downloads/
  TC-SPC-XBS-017  --report → JSON sidecar (*_data.json) written alongside HTML
  TC-SPC-XBS-018  JSON sidecar: report_type == "pv", verdict_pass is True for stable data
"""

import glob
import os
import subprocess
import time

import re as _re

from conftest import PROJECT_ROOT, MODULE_ROOT, run, combined, data, extract_float


DOWNLOADS = os.path.expanduser("~/Downloads")


def _recent_png(pattern, t_start):
    return [
        f for f in glob.glob(os.path.join(DOWNLOADS, pattern))
        if os.path.getmtime(f) >= t_start
    ]


class TestXbarS:

    def test_tc_spc_xbs_001_happy_path_exits_zero(self):
        """
        TC-SPC-XBS-001:
        Stable 20-subgroup / n=8 dataset → exit 0.
        Output must contain X-bar and S chart sections and a verdict.
        """
        r = run("jrc_spc_xbar_s.R", data("xbar_s_stable.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "X-bar" in out or "Xbar" in out or "Grand Mean" in out or \
               "grand mean" in out.lower(), "X-bar section missing"
        assert "Std Dev" in out or "S-bar" in out or "S_bar" in out or \
               "standard deviation" in out.lower(), "S chart section missing"
        assert "Verdict" in out or "IN CONTROL" in out or "OUT OF CONTROL" in out, \
            "Verdict missing"

    def test_tc_spc_xbs_002_stable_data_in_control(self):
        """
        TC-SPC-XBS-002:
        The stable dataset is designed so all subgroup means and standard
        deviations fall within their control limits. Verdict must be in-control.
        """
        r = run("jrc_spc_xbar_s.R", data("xbar_s_stable.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "IN CONTROL" in out or "STABLE" in out, \
            f"Expected in-control verdict:\n{out}"

    def test_tc_spc_xbs_003_ooc_data_exits_zero(self):
        """
        TC-SPC-XBS-003:
        OOC dataset (subgroup sg09 mean ≈ 102, far above UCL ≈ 100.55)
        → exit 0 with OUT OF CONTROL in output.
        """
        r = run("jrc_spc_xbar_s.R", data("xbar_s_ooc.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "OUT OF CONTROL" in out or "SIGNALS" in out, \
            f"Expected out-of-control signal:\n{out}"

    def test_tc_spc_xbs_004_ooc_subgroup_flagged(self):
        """
        TC-SPC-XBS-004:
        Subgroup sg09 must be identified as a violation in the output.
        """
        r = run("jrc_spc_xbar_s.R", data("xbar_s_ooc.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "sg09" in out, f"Expected 'sg09' in violation output:\n{out}"

    def test_tc_spc_xbs_005_user_limits(self):
        """
        TC-SPC-XBS-005:
        When --ucl and --lcl are provided, output must acknowledge
        user-specified limits and exit 0.
        """
        r = run("jrc_spc_xbar_s.R", data("xbar_s_stable.csv"),
                "--ucl", "102.0", "--lcl", "98.0")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "user" in out.lower() or "specified" in out.lower() or \
               "102.0" in out or "102.00" in out, \
            f"Expected user-specified UCL mentioned:\n{out}"

    def test_tc_spc_xbs_006_png_created(self):
        """
        TC-SPC-XBS-006:
        A PNG file matching *_jrc_spc_xbar_s.png must be created in ~/Downloads/.
        """
        t_start = time.time()
        r = run("jrc_spc_xbar_s.R", data("xbar_s_stable.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        recent = _recent_png("*_jrc_spc_xbar_s.png", t_start)
        assert recent, "No *_jrc_spc_xbar_s.png found in ~/Downloads/ after run"

    def test_tc_spc_xbs_007_no_arguments(self):
        """
        TC-SPC-XBS-007:
        Calling with no arguments must exit non-zero and print a usage message.
        """
        r = run("jrc_spc_xbar_s.R")
        assert r.returncode != 0, "Expected non-zero exit with no arguments"
        out = combined(r)
        assert "Usage" in out or "usage" in out, \
            f"Expected usage message:\n{out}"

    def test_tc_spc_xbs_008_file_not_found(self):
        """
        TC-SPC-XBS-008:
        A non-existent CSV path must exit non-zero with an appropriate message.
        """
        r = run("jrc_spc_xbar_s.R", "/tmp/no_such_file_xyz.csv")
        assert r.returncode != 0, "Expected non-zero exit for missing file"
        out = combined(r)
        assert "not found" in out.lower() or "no_such_file" in out, \
            f"Expected 'not found' message:\n{out}"

    def test_tc_spc_xbs_009_missing_column(self):
        """
        TC-SPC-XBS-009:
        A CSV missing the 'value' column must exit non-zero and name the
        missing column in the output.
        """
        r = run("jrc_spc_xbar_s.R", data("xbar_s_missing_col.csv"))
        assert r.returncode != 0, "Expected non-zero exit for missing column"
        out = combined(r)
        assert "value" in out.lower(), \
            f"Expected 'value' mentioned in error:\n{out}"

    def test_tc_spc_xbs_010_unbalanced_subgroups(self):
        """
        TC-SPC-XBS-010:
        A dataset with unequal subgroup sizes must exit non-zero.
        Reuses the xbar_r unbalanced dataset (same column structure).
        """
        r = run("jrc_spc_xbar_s.R", data("xbar_r_unbalanced.csv"))
        assert r.returncode != 0, "Expected non-zero exit for unbalanced subgroups"
        out = combined(r)
        assert any(kw in out.lower() for kw in ("unbalanced", "equal", "same size")), \
            f"Expected unbalanced-design message:\n{out}"

    def test_tc_spc_xbs_011_bypass_protection(self):
        """
        TC-SPC-XBS-011:
        Calling jrc_spc_xbar_s.R directly via Rscript without RENV_PATHS_ROOT
        must exit non-zero and mention RENV_PATHS_ROOT in the error output.
        """
        script = os.path.join(MODULE_ROOT, "R", "jrc_spc_xbar_s.R")
        env = {k: v for k, v in os.environ.items() if k != "RENV_PATHS_ROOT"}
        result = subprocess.run(
            ["Rscript", script, data("xbar_s_stable.csv")],
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


def _extract_section_float(result, section_start, section_end, label):
    """Extract a float from the region between section_start and section_end markers."""
    out = combined(result)
    m_sec = _re.search(
        rf"{_re.escape(section_start)}.*?(?={_re.escape(section_end)})",
        out, _re.DOTALL,
    )
    if not m_sec:
        return None
    m = _re.search(rf"{_re.escape(label)}\s+([-\d.]+)", m_sec.group(0))
    return float(m.group(1)) if m else None


class TestXbarSNumeric:
    """Numeric correctness assertions — see module docstring for derivations."""

    def test_tc_spc_xbs_012_grand_xbar_exact(self):
        """
        TC-SPC-XBS-012:
        Grand X-bar for xbar_s_stable.csv = 100.060 ± 0.001.
        """
        r = run("jrc_spc_xbar_s.R", data("xbar_s_stable.csv"), "value", "subgroup")
        assert r.returncode == 0, combined(r)
        xbar = extract_float(r, "X-dbar):")
        print(f"  Grand X-bar: extracted = {xbar}")
        assert xbar is not None, f"Grand X-bar not found in output:\n{combined(r)}"
        print(f"  Grand X-bar: expected 100.060 ± 0.001, got {xbar:.4f}")
        assert abs(xbar - 100.060) < 0.001, \
            f"Expected grand X-bar = 100.060 ± 0.001, got {xbar:.4f}"

    def test_tc_spc_xbs_013_ucl_xbar_exact(self):
        """
        TC-SPC-XBS-013:
        UCL (X-bar chart) = 100.5807 ± 0.001.
        Independent reference: X-bar + A3*s-bar = 100.060 + 1.099095*0.473726 = 100.5807.
        """
        r = run("jrc_spc_xbar_s.R", data("xbar_s_stable.csv"), "value", "subgroup")
        assert r.returncode == 0, combined(r)
        ucl = _extract_section_float(r, "X-bar Chart", "--- S Chart", "UCL:")
        print(f"  UCL_x: extracted = {ucl}")
        assert ucl is not None, f"UCL (X-bar) not found in output:\n{combined(r)}"
        print(f"  UCL_x: expected 100.5807 ± 0.001, got {ucl:.4f}")
        assert abs(ucl - 100.5807) < 0.001, \
            f"Expected UCL (X-bar) = 100.5807 ± 0.001, got {ucl:.4f}"

    def test_tc_spc_xbs_014_lcl_xbar_exact(self):
        """
        TC-SPC-XBS-014:
        LCL (X-bar chart) = 99.5393 ± 0.001.
        Independent reference: X-bar - A3*s-bar = 100.060 - 1.099095*0.473726 = 99.5393.
        """
        r = run("jrc_spc_xbar_s.R", data("xbar_s_stable.csv"), "value", "subgroup")
        assert r.returncode == 0, combined(r)
        lcl = _extract_section_float(r, "X-bar Chart", "--- S Chart", "LCL:")
        print(f"  LCL_x: extracted = {lcl}")
        assert lcl is not None, f"LCL (X-bar) not found in output:\n{combined(r)}"
        print(f"  LCL_x: expected 99.5393 ± 0.001, got {lcl:.4f}")
        assert abs(lcl - 99.5393) < 0.001, \
            f"Expected LCL (X-bar) = 99.5393 ± 0.001, got {lcl:.4f}"

    def test_tc_spc_xbs_015_ucl_s_exact(self):
        """
        TC-SPC-XBS-015:
        UCL (S chart) = 0.8598 ± 0.001.
        Independent reference: B4 * s-bar = 1.814910 * 0.473726 = 0.8598.
        """
        r = run("jrc_spc_xbar_s.R", data("xbar_s_stable.csv"), "value", "subgroup")
        assert r.returncode == 0, combined(r)
        ucl_s = _extract_section_float(r, "--- S Chart", "--- Verdict", "UCL:")
        print(f"  UCL_s: extracted = {ucl_s}")
        assert ucl_s is not None, f"UCL (S chart) not found in output:\n{combined(r)}"
        print(f"  UCL_s: expected 0.8598 ± 0.001, got {ucl_s:.4f}")
        assert abs(ucl_s - 0.8598) < 0.001, \
            f"Expected UCL (S) = 0.8598 ± 0.001, got {ucl_s:.4f}"


class TestXbarSReport:

    def test_tc_spc_xbs_016_report_html_created(self):
        """
        TC-SPC-XBS-016:
        --report flag → exit 0 and HTML report file written to ~/Downloads/.
        """
        t_start = time.time()
        r = run("jrc_spc_xbar_s.R", data("xbar_s_stable.csv"), "--report")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        html_files = [
            f for f in glob.glob(os.path.join(DOWNLOADS, "*_xbar_s_pv_report.html"))
            if os.path.getmtime(f) >= t_start
        ]
        assert html_files, "No *_xbar_s_pv_report.html found in ~/Downloads/ after --report run"

    def test_tc_spc_xbs_017_report_json_sidecar_created(self):
        """
        TC-SPC-XBS-017:
        --report flag → JSON sidecar (*_data.json) written alongside HTML in ~/Downloads/.
        """
        t_start = time.time()
        r = run("jrc_spc_xbar_s.R", data("xbar_s_stable.csv"), "--report")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        json_files = [
            f for f in glob.glob(os.path.join(DOWNLOADS, "*_xbar_s_pv_report_data.json"))
            if os.path.getmtime(f) >= t_start
        ]
        assert json_files, "No *_xbar_s_pv_report_data.json found in ~/Downloads/ after --report run"

    def test_tc_spc_xbs_018_report_json_content(self):
        """
        TC-SPC-XBS-018:
        JSON sidecar contains report_type == "pv" and verdict_pass == True
        for a stable in-control dataset (TC-SPC-XBS-002 confirms IN CONTROL verdict).
        """
        import json
        t_start = time.time()
        r = run("jrc_spc_xbar_s.R", data("xbar_s_stable.csv"), "--report")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        json_files = [
            f for f in glob.glob(os.path.join(DOWNLOADS, "*_xbar_s_pv_report_data.json"))
            if os.path.getmtime(f) >= t_start
        ]
        assert json_files, "No JSON sidecar found — cannot check content"
        with open(json_files[-1]) as fh:
            d = json.load(fh)
        assert d.get("report_type") == "pv", \
            f"Expected report_type 'pv', got {d.get('report_type')!r}"
        assert isinstance(d.get("verdict_pass"), bool), \
            f"Expected verdict_pass to be boolean, got {type(d.get('verdict_pass'))}"
        assert d["verdict_pass"] is True, \
            "Expected verdict_pass True for stable in-control dataset"
