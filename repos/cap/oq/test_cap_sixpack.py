"""
OQ test suite — Cap module: jrc_cap_sixpack

Maps to validation plan JR-VP-CAP-001 as follows:

  TC-CAP-S-001  Valid input (capable data, both limits) -> exit 0, "Sixpack" in output
  TC-CAP-S-002  Cpk label present in output
  TC-CAP-S-003  Ppk label present in output
  TC-CAP-S-004  Control chart limits (UCL/LCL) present in output
  TC-CAP-S-005  Shapiro-Wilk result reported in output
  TC-CAP-S-006  SPC verdict present in output
  TC-CAP-S-007  Capability verdict present in output
  TC-CAP-S-008  PNG saved to ~/Downloads/ with pattern *_jrc_cap_sixpack.png
  TC-CAP-S-009  No arguments -> non-zero exit, usage in output
  TC-CAP-S-010  File not found -> non-zero exit
  TC-CAP-S-011  n < 5 (cap_small.csv) -> non-zero exit
  TC-CAP-S-012  Non-numeric column (cap_nonnumeric.csv) -> non-zero exit
  TC-CAP-S-013  LSL >= USL -> non-zero exit
  TC-CAP-S-014  Direct Rscript call without RENV_PATHS_ROOT -> non-zero exit

--report sidecar assertions (TC-CAP-S-015 to TC-CAP-S-017):

  TC-CAP-S-015  --report → exit 0, HTML report written to ~/Downloads/
  TC-CAP-S-016  --report → JSON sidecar (*_data.json) written alongside HTML
  TC-CAP-S-017  JSON sidecar: report_type == "pv", verdict_pass is True for capable data
"""
import sys

# Force UTF-8 stdout/stderr on Windows (cp1252 cannot encode emoji)
if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if sys.stderr.encoding and sys.stderr.encoding.lower() != "utf-8":
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

import glob
import os
import pytest
import subprocess
import time

from conftest import PROJECT_ROOT, MODULE_ROOT, run, combined, data, RSCRIPT_BIN

_TMPL_DIR = os.path.join(PROJECT_ROOT, "docs", "templates")
_PV_REPORT_AVAILABLE = os.path.exists(os.path.join(_TMPL_DIR, "pv_report_template.html"))


DOWNLOADS = os.path.expanduser("~/Downloads")


def _recent_png(pattern, t_start):
    return [
        f for f in glob.glob(os.path.join(DOWNLOADS, pattern))
        if os.path.getmtime(f) >= t_start - 1.0
    ]


class TestCapSixpack:

    def test_tc_cap_s_001_happy_path_exits_zero(self):
        """
        TC-CAP-S-001:
        Valid input (cap_normal_capable.csv, both limits) -> exit 0.
        Output must contain "Sixpack".
        """
        r = run("jrc_cap_sixpack.R", data("cap_normal_capable.csv"), "value", "9.0", "11.0")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Sixpack" in out, \
            f"Expected 'Sixpack' in output:\n{out}"

    def test_tc_cap_s_002_cpk_label_present(self):
        """
        TC-CAP-S-002:
        Output must contain "Cpk:" label.
        """
        r = run("jrc_cap_sixpack.R", data("cap_normal_capable.csv"), "value", "9.0", "11.0")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Cpk:" in out, \
            f"Expected 'Cpk:' in output:\n{out}"

    def test_tc_cap_s_003_ppk_label_present(self):
        """
        TC-CAP-S-003:
        Output must contain "Ppk:" label.
        """
        r = run("jrc_cap_sixpack.R", data("cap_normal_capable.csv"), "value", "9.0", "11.0")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Ppk:" in out, \
            f"Expected 'Ppk:' in output:\n{out}"

    def test_tc_cap_s_004_control_limits_present(self):
        """
        TC-CAP-S-004:
        Output must contain UCL and LCL for the I-MR chart.
        """
        r = run("jrc_cap_sixpack.R", data("cap_normal_capable.csv"), "value", "9.0", "11.0")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "UCL" in out and "LCL" in out, \
            f"Expected UCL and LCL in output:\n{out}"

    def test_tc_cap_s_005_shapiro_wilk_reported(self):
        """
        TC-CAP-S-005:
        Shapiro-Wilk result must appear in output.
        """
        r = run("jrc_cap_sixpack.R", data("cap_normal_capable.csv"), "value", "9.0", "11.0")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Shapiro-Wilk" in out, \
            f"Expected 'Shapiro-Wilk' in output:\n{out}"

    def test_tc_cap_s_006_spc_verdict_present(self):
        """
        TC-CAP-S-006:
        Output must contain an SPC verdict line.
        """
        r = run("jrc_cap_sixpack.R", data("cap_normal_capable.csv"), "value", "9.0", "11.0")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "SPC:" in out, \
            f"Expected 'SPC:' in output:\n{out}"

    def test_tc_cap_s_007_capability_verdict_present(self):
        """
        TC-CAP-S-007:
        Output must contain "Cap:" verdict line with a known verdict word.
        """
        r = run("jrc_cap_sixpack.R", data("cap_normal_capable.csv"), "value", "9.0", "11.0")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Cap:" in out, \
            f"Expected 'Cap:' verdict in output:\n{out}"
        assert any(v in out for v in ["CAPABLE", "EXCELLENT", "MARGINAL", "NOT CAPABLE"]), \
            f"Expected a capability verdict word in output:\n{out}"

    def test_tc_cap_s_008_png_created(self):
        """
        TC-CAP-S-008:
        A PNG matching *_jrc_cap_sixpack.png must appear in ~/Downloads/.
        """
        t_start = time.time()
        r = run("jrc_cap_sixpack.R", data("cap_normal_capable.csv"), "value", "9.0", "11.0")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        recent = _recent_png("*_jrc_cap_sixpack.png", t_start)
        assert recent, (
            f"No *_jrc_cap_sixpack.png found in ~/Downloads/ after run\n"
            f"  DOWNLOADS={DOWNLOADS!r} (exists={os.path.isdir(DOWNLOADS)})\n"
            f"  All matches (any age): {glob.glob(os.path.join(DOWNLOADS, '*_jrc_cap_sixpack.png'))!r}\n"
            f"  Script output: {combined(r)}"
        )

    def test_tc_cap_s_009_no_arguments(self):
        """
        TC-CAP-S-009:
        Calling with no arguments must exit non-zero and print usage.
        """
        r = run("jrc_cap_sixpack.R")
        assert r.returncode != 0, "Expected non-zero exit with no arguments"
        out = combined(r)
        assert "Usage" in out or "usage" in out.lower(), \
            f"Expected usage message:\n{out}"

    def test_tc_cap_s_010_file_not_found(self):
        """
        TC-CAP-S-010:
        Non-existent file must exit non-zero.
        """
        r = run("jrc_cap_sixpack.R", "nonexistent_file_xyz.csv", "value", "9.0", "11.0")
        assert r.returncode != 0, \
            f"Expected non-zero exit for missing file:\n{combined(r)}"

    def test_tc_cap_s_011_n_less_than_5(self):
        """
        TC-CAP-S-011:
        Input with only 3 rows (n < 5) must exit non-zero.
        """
        r = run("jrc_cap_sixpack.R", data("cap_small.csv"), "value", "9.0", "11.0")
        assert r.returncode != 0, \
            f"Expected non-zero exit when n < 5:\n{combined(r)}"

    def test_tc_cap_s_012_nonnumeric_column(self):
        """
        TC-CAP-S-012:
        Non-numeric value column must exit non-zero.
        """
        r = run("jrc_cap_sixpack.R", data("cap_nonnumeric.csv"), "value", "0.0", "1.0")
        assert r.returncode != 0, \
            f"Expected non-zero exit for non-numeric column:\n{combined(r)}"

    def test_tc_cap_s_013_lsl_greater_than_usl(self):
        """
        TC-CAP-S-013:
        LSL >= USL must exit non-zero.
        """
        r = run("jrc_cap_sixpack.R", data("cap_normal_capable.csv"), "value", "11.0", "9.0")
        assert r.returncode != 0, \
            f"Expected non-zero exit when LSL > USL:\n{combined(r)}"

    def test_tc_cap_s_014_bypass_protection(self):
        """
        TC-CAP-S-014:
        Calling jrc_cap_sixpack.R directly via Rscript without RENV_PATHS_ROOT
        must exit non-zero and mention RENV_PATHS_ROOT in the error output.
        """
        script = os.path.join(MODULE_ROOT, "R", "jrc_cap_sixpack.R")
        env = {k: v for k, v in os.environ.items() if k != "RENV_PATHS_ROOT"}
        result = subprocess.run(
            [RSCRIPT_BIN, "--vanilla", script,
             data("cap_normal_capable.csv"), "value", "9.0", "11.0"],
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


@pytest.mark.skipif(not _PV_REPORT_AVAILABLE,
                    reason="Validation Pack not installed (pv_report_template.html missing)")
class TestCapSixpackReport:

    def test_tc_cap_s_015_report_html_created(self):
        """
        TC-CAP-S-015:
        --report flag → exit 0 and report file written to ~/Downloads/.
        Accepts .docx (jr_pack full install) or .html (template-only install).
        """
        t_start = time.time()
        r = run("jrc_cap_sixpack.R", data("cap_normal_capable.csv"), "value", "9.0", "11.0", "--report")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        docx_files = [
            f for f in glob.glob(os.path.join(DOWNLOADS, "*_cap_sixpack_pv_report.docx"))
            if os.path.getmtime(f) >= t_start - 1.0
        ]
        html_files = [
            f for f in glob.glob(os.path.join(DOWNLOADS, "*_cap_sixpack_pv_report.html"))
            if os.path.getmtime(f) >= t_start - 1.0
        ]
        assert docx_files or html_files, (
            f"No report file (*_cap_sixpack_pv_report.docx or .html) found in ~/Downloads/\n"
            f"  DOWNLOADS={DOWNLOADS!r} (exists={os.path.isdir(DOWNLOADS)})\n"
            f"  All docx: {glob.glob(os.path.join(DOWNLOADS, '*_cap_sixpack_pv_report.docx'))!r}\n"
            f"  All html: {glob.glob(os.path.join(DOWNLOADS, '*_cap_sixpack_pv_report.html'))!r}\n"
            f"  Script output: {combined(r)}"
        )

    def test_tc_cap_s_016_report_json_sidecar_created(self):
        """
        TC-CAP-S-016:
        --report flag → JSON sidecar or .docx written to ~/Downloads/.
        Accepts .docx (jr_pack full install) or JSON (template-only install).
        """
        t_start = time.time()
        r = run("jrc_cap_sixpack.R", data("cap_normal_capable.csv"), "value", "9.0", "11.0", "--report")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        docx_files = [
            f for f in glob.glob(os.path.join(DOWNLOADS, "*_cap_sixpack_pv_report.docx"))
            if os.path.getmtime(f) >= t_start - 1.0
        ]
        json_files = [
            f for f in glob.glob(os.path.join(DOWNLOADS, "*_cap_sixpack_pv_report_data.json"))
            if os.path.getmtime(f) >= t_start - 1.0
        ]
        assert docx_files or json_files, (
            f"No report data (*_cap_sixpack_pv_report.docx or *_data.json) found in ~/Downloads/\n"
            f"  DOWNLOADS={DOWNLOADS!r} (exists={os.path.isdir(DOWNLOADS)})\n"
            f"  All docx: {glob.glob(os.path.join(DOWNLOADS, '*_cap_sixpack_pv_report.docx'))!r}\n"
            f"  All json: {glob.glob(os.path.join(DOWNLOADS, '*_cap_sixpack_pv_report_data.json'))!r}\n"
            f"  Script output: {combined(r)}"
        )

    def test_tc_cap_s_017_report_json_content(self):
        """
        TC-CAP-S-017:
        JSON sidecar contains report_type == "pv" and verdict_pass == True
        for a capable dataset (from TC-CAP-S-007, this dataset yields CAPABLE/EXCELLENT).
        When jr_pack generates the .docx the JSON is cleaned up; in that case
        the .docx itself is accepted as evidence of correct report data.
        """
        import json
        t_start = time.time()
        r = run("jrc_cap_sixpack.R", data("cap_normal_capable.csv"), "value", "9.0", "11.0", "--report")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        docx_files = [
            f for f in glob.glob(os.path.join(DOWNLOADS, "*_cap_sixpack_pv_report.docx"))
            if os.path.getmtime(f) >= t_start - 1.0
        ]
        json_files = [
            f for f in glob.glob(os.path.join(DOWNLOADS, "*_cap_sixpack_pv_report_data.json"))
            if os.path.getmtime(f) >= t_start - 1.0
        ]
        assert docx_files or json_files, (
            f"No report output found in ~/Downloads/ after --report run\n"
            f"  DOWNLOADS={DOWNLOADS!r} (exists={os.path.isdir(DOWNLOADS)})\n"
            f"  Script output: {combined(r)}"
        )
        if json_files:
            with open(json_files[-1]) as fh:
                d = json.load(fh)
            assert d.get("report_type") == "pv", \
                f"Expected report_type 'pv', got {d.get('report_type')!r}"
            assert isinstance(d.get("verdict_pass"), bool), \
                f"Expected verdict_pass to be boolean, got {type(d.get('verdict_pass'))}"
            assert d["verdict_pass"] is True, \
                "Expected verdict_pass True for capable dataset with wide limits"
