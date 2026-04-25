"""
OQ test suite — MSA module: jrc_msa_gauge_rr

Maps to validation plan JR-VP-MSA-001 as follows:

  TC-MSA-GRR-001  Balanced dataset → exit 0, key output sections present
  TC-MSA-GRR-002  Known dataset → %GRR in expected range, verdict ACCEPTABLE
  TC-MSA-GRR-003  --tolerance flag → %GRR vs tolerance reported, exit 0
  TC-MSA-GRR-004  PNG written to ~/Downloads/
  TC-MSA-GRR-005  No arguments → non-zero exit, usage message
  TC-MSA-GRR-006  File not found → non-zero exit
  TC-MSA-GRR-007  Missing column → non-zero exit, column name in output
  TC-MSA-GRR-008  Unbalanced design → non-zero exit, 'unbalanced' in output
  TC-MSA-GRR-009  Single operator → non-zero exit
  TC-MSA-GRR-010  Bypass protection — direct Rscript call fails

Numeric correctness assertions (TC-MSA-GRR-011 to TC-MSA-GRR-013):

  These test cases assert that key GRR metrics match independently computed
  reference values, providing quantitative correctness evidence for audit.

  Reference dataset: gauge_rr_balanced.csv (10 parts × 3 operators × 3 reps)
  Independent computation: AIAG MSA 4th ed. ANOVA method, implemented in Python
  (see repos/msa/oq/data/ comments). Results:
    %GRR (%Study Var) = 4.15%  (independent Python ANOVA: 4.1476%)
    Part-to-Part %    = 99.91%
    ndc               = 33

  TC-MSA-GRR-011  %GRR extracted from output = 4.15% ± 0.10%
  TC-MSA-GRR-012  ndc extracted from output  = 33 (exact integer)
  TC-MSA-GRR-013  Part-to-Part % ≈ 99.91% ± 0.20%

--report sidecar assertions (TC-MSA-GRR-014 to TC-MSA-GRR-016):

  TC-MSA-GRR-014  --report → exit 0, HTML report written to ~/Downloads/
  TC-MSA-GRR-015  --report → JSON sidecar (*_data.json) written alongside HTML
  TC-MSA-GRR-016  JSON sidecar: report_type == "msa", verdict_pass is True for acceptable GRR
"""

import glob
import os
import re
import subprocess
import time

from conftest import PROJECT_ROOT, MODULE_ROOT, run, combined, data, extract_float


DOWNLOADS = os.path.expanduser("~/Downloads")


def _recent_png(pattern, t_start):
    """Return list of PNGs matching pattern in ~/Downloads created after t_start."""
    return [
        f for f in glob.glob(os.path.join(DOWNLOADS, pattern))
        if os.path.getmtime(f) >= t_start
    ]


# ===========================================================================
# OQ tests
# ===========================================================================

class TestGaugeRR:

    def test_tc_msa_grr_001_happy_path_exits_zero(self):
        """
        TC-MSA-GRR-001:
        Balanced 10-part / 3-operator / 3-replicate dataset → exit 0.
        Output must contain ANOVA table header, variance components section,
        study variation section, and a verdict line.
        """
        r = run("jrc_msa_gauge_rr.R", data("gauge_rr_balanced.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "ANOVA" in out,               "ANOVA table header missing"
        assert "Variance Components" in out, "Variance components section missing"
        assert "Study Variation" in out,     "Study variation section missing"
        assert "Verdict" in out,             "Verdict section missing"
        assert "Gauge R&R" in out,           "'Gauge R&R' label missing"

    def test_tc_msa_grr_002_known_data_grr_range(self):
        """
        TC-MSA-GRR-002:
        The balanced sample dataset is designed so that part-to-part variation
        dominates. %GRR must be below 15% and the verdict must be ACCEPTABLE.
        """
        r = run("jrc_msa_gauge_rr.R", data("gauge_rr_balanced.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)

        # Extract %GRR value from the Verdict line: "  %GRR (%%Study Var): X.XX%  →  ..."
        m = re.search(r"%GRR\s*\(%Study Var\)[:\s]+([\d.]+)%", out)
        assert m, f"Could not parse %%GRR from output:\n{out}"
        pct_grr = float(m.group(1))
        assert pct_grr < 15.0, f"%%GRR = {pct_grr:.2f}%% — expected < 15%% for this dataset"

        assert "ACCEPTABLE" in out, f"Expected verdict ACCEPTABLE:\n{out}"

    def test_tc_msa_grr_003_tolerance_flag(self):
        """
        TC-MSA-GRR-003:
        When --tolerance 1.0 is passed, the output must include a %GRR vs
        tolerance line. Exit code must be 0.
        """
        r = run("jrc_msa_gauge_rr.R", data("gauge_rr_balanced.csv"),
                "--tolerance", "1.0")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Tolerance" in out or "tolerance" in out, \
            f"Expected tolerance line in output:\n{out}"

    def test_tc_msa_grr_004_png_created(self):
        """
        TC-MSA-GRR-004:
        A PNG file matching *_jrc_msa_gauge_rr.png must be created in
        ~/Downloads/ during this run.
        """
        t_start = time.time()
        r = run("jrc_msa_gauge_rr.R", data("gauge_rr_balanced.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        recent = _recent_png("*_jrc_msa_gauge_rr.png", t_start)
        assert recent, \
            "No *_jrc_msa_gauge_rr.png found in ~/Downloads/ after run"

    def test_tc_msa_grr_005_no_arguments(self):
        """
        TC-MSA-GRR-005:
        Calling with no arguments must exit non-zero and print a usage message.
        """
        r = run("jrc_msa_gauge_rr.R")
        assert r.returncode != 0, "Expected non-zero exit with no arguments"
        out = combined(r)
        assert "Usage" in out or "usage" in out, \
            f"Expected usage message:\n{out}"

    def test_tc_msa_grr_006_file_not_found(self):
        """
        TC-MSA-GRR-006:
        A non-existent CSV path must exit non-zero with a message containing
        'not found' or the filename.
        """
        r = run("jrc_msa_gauge_rr.R", "/tmp/does_not_exist_xyz.csv")
        assert r.returncode != 0, "Expected non-zero exit for missing file"
        out = combined(r)
        assert "not found" in out.lower() or "does_not_exist" in out, \
            f"Expected 'not found' or filename in output:\n{out}"

    def test_tc_msa_grr_007_missing_column(self):
        """
        TC-MSA-GRR-007:
        A CSV missing the 'operator' column must exit non-zero and name the
        missing column in the error output.
        """
        r = run("jrc_msa_gauge_rr.R", data("gauge_rr_missing_col.csv"))
        assert r.returncode != 0, "Expected non-zero exit for missing column"
        out = combined(r)
        assert "operator" in out.lower(), \
            f"Expected 'operator' mentioned in error:\n{out}"

    def test_tc_msa_grr_008_unbalanced_design(self):
        """
        TC-MSA-GRR-008:
        An unbalanced dataset (unequal replicates per cell) must exit non-zero
        and mention 'unbalanced' or 'replicates' in the output.
        """
        r = run("jrc_msa_gauge_rr.R", data("gauge_rr_unbalanced.csv"))
        assert r.returncode != 0, "Expected non-zero exit for unbalanced design"
        out = combined(r)
        assert any(kw in out.lower() for kw in ("unbalanced", "replicates", "equal")), \
            f"Expected unbalanced-design message:\n{out}"

    def test_tc_msa_grr_009_single_operator(self):
        """
        TC-MSA-GRR-009:
        A dataset with only one operator must exit non-zero. Gauge R&R requires
        at least two operators to estimate reproducibility.
        """
        r = run("jrc_msa_gauge_rr.R", data("gauge_rr_one_operator.csv"))
        assert r.returncode != 0, "Expected non-zero exit with only one operator"

    def test_tc_msa_grr_010_bypass_protection(self):
        """
        TC-MSA-GRR-010:
        Calling jrc_msa_gauge_rr.R directly via Rscript without RENV_PATHS_ROOT
        must exit non-zero and mention RENV_PATHS_ROOT in the error output.
        """
        script = os.path.join(MODULE_ROOT, "R", "jrc_msa_gauge_rr.R")
        env = {k: v for k, v in os.environ.items() if k != "RENV_PATHS_ROOT"}
        result = subprocess.run(
            ["Rscript", script, data("gauge_rr_balanced.csv")],
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


class TestMsaGaugeRrNumeric:
    """Numeric correctness assertions — see module docstring for derivations."""

    def test_tc_msa_grr_011_pct_grr_exact(self):
        """
        TC-MSA-GRR-011:
        %GRR (%Study Var) for gauge_rr_balanced.csv = 4.15% ± 0.10%.
        Independent reference: AIAG MSA 4th ed. ANOVA method computed in Python
        gives 4.1476% from the same data.
        """
        r = run("jrc_msa_gauge_rr.R", data("gauge_rr_balanced.csv"))
        assert r.returncode == 0, combined(r)
        m = re.search(r"%GRR\s*\(%Study Var\)[:\s]+([\d.]+)%", combined(r))
        assert m, f"%GRR value not found in output:\n{combined(r)}"
        pct_grr = float(m.group(1))
        print(f"  %GRR: expected 4.15% ± 0.10%, got {pct_grr:.2f}%")
        assert abs(pct_grr - 4.15) < 0.10, \
            f"Expected %GRR = 4.15% ± 0.10%, got {pct_grr:.2f}%"

    def test_tc_msa_grr_012_ndc_exact(self):
        """
        TC-MSA-GRR-012:
        ndc for gauge_rr_balanced.csv = 33 (exact integer).
        Independent reference: ndc = floor(1.41 * sqrt(var_part) / GRR) = 33.
        """
        r = run("jrc_msa_gauge_rr.R", data("gauge_rr_balanced.csv"))
        assert r.returncode == 0, combined(r)
        m = re.search(r"ndc:\s+(\d+)", combined(r))
        assert m, f"ndc not found in output:\n{combined(r)}"
        ndc = int(m.group(1))
        print(f"  ndc: expected 33 (exact), got {ndc}")
        assert ndc == 33, f"Expected ndc = 33, got {ndc}"

    def test_tc_msa_grr_013_part_to_part_pct_exact(self):
        """
        TC-MSA-GRR-013:
        Part-to-Part % for gauge_rr_balanced.csv = 99.91% ± 0.20%.
        Independent reference: P:P std dev / TV = 0.35203 / 0.35233 = 99.91%.
        """
        r = run("jrc_msa_gauge_rr.R", data("gauge_rr_balanced.csv"))
        assert r.returncode == 0, combined(r)
        m = re.search(r"Part-to-Part\s+[\d.]+\s+([\d.]+)%", combined(r))
        assert m, f"Part-to-Part % not found in output:\n{combined(r)}"
        pct_pt = float(m.group(1))
        print(f"  Part-to-Part %: expected 99.91% ± 0.20%, got {pct_pt:.2f}%")
        assert abs(pct_pt - 99.91) < 0.20, \
            f"Expected Part-to-Part = 99.91% ± 0.20%, got {pct_pt:.2f}%"


class TestGaugeRRReport:

    def test_tc_msa_grr_014_report_html_created(self):
        """
        TC-MSA-GRR-014:
        --report flag → exit 0 and HTML report file written to ~/Downloads/.
        """
        t_start = time.time()
        r = run("jrc_msa_gauge_rr.R", data("gauge_rr_balanced.csv"), "--report")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        html_files = [
            f for f in glob.glob(os.path.join(DOWNLOADS, "*_gauge_rr_report.html"))
            if os.path.getmtime(f) >= t_start
        ]
        assert html_files, "No *_gauge_rr_report.html found in ~/Downloads/ after --report run"

    def test_tc_msa_grr_015_report_json_sidecar_created(self):
        """
        TC-MSA-GRR-015:
        --report flag → JSON sidecar (*_data.json) written alongside HTML in ~/Downloads/.
        """
        t_start = time.time()
        r = run("jrc_msa_gauge_rr.R", data("gauge_rr_balanced.csv"), "--report")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        json_files = [
            f for f in glob.glob(os.path.join(DOWNLOADS, "*_gauge_rr_report_data.json"))
            if os.path.getmtime(f) >= t_start
        ]
        assert json_files, "No *_gauge_rr_report_data.json found in ~/Downloads/ after --report run"

    def test_tc_msa_grr_016_report_json_content(self):
        """
        TC-MSA-GRR-016:
        JSON sidecar contains report_type == "msa" and verdict_pass == True.
        TC-MSA-GRR-002 confirms %GRR ≈ 4.15%, well within the 10% threshold.
        """
        import json
        t_start = time.time()
        r = run("jrc_msa_gauge_rr.R", data("gauge_rr_balanced.csv"), "--report")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        json_files = [
            f for f in glob.glob(os.path.join(DOWNLOADS, "*_gauge_rr_report_data.json"))
            if os.path.getmtime(f) >= t_start
        ]
        assert json_files, "No JSON sidecar found — cannot check content"
        with open(json_files[-1]) as fh:
            d = json.load(fh)
        assert d.get("report_type") == "msa", \
            f"Expected report_type 'msa', got {d.get('report_type')!r}"
        assert isinstance(d.get("verdict_pass"), bool), \
            f"Expected verdict_pass to be boolean, got {type(d.get('verdict_pass'))}"
        assert d["verdict_pass"] is True, \
            "Expected verdict_pass True: %GRR ≈ 4.15%, well within 10% acceptance threshold"
