"""
OQ test suite — Design of Experiments scripts.

Covers: jrc_doe_design (TC-DOE-DES-001..012), jrc_doe_analyse (TC-DOE-ANA-001..008)
"""

import os
import re
import glob
import pytest
from conftest import run, combined, DATA_DIR


def data(name):
    return os.path.join(DATA_DIR, name)


# ===========================================================================
# jrc_doe_design (TC-DOE-DES-001 .. 012)
# ===========================================================================

class TestDoeDesign:

    def test_tc_doe_des_001_full2_3factor_basic(self, tmp_path):
        """TC-DOE-DES-001: full2, 3 factors, no centre points → exit 0, HTML and CSV created"""
        r = run("jrc_doe_design.R", "full2", data("doe_factors_3f_2level.csv"),
                "SealStrength_N", str(tmp_path))
        assert r.returncode == 0
        html_files = list(tmp_path.glob("doe_design_full2_*.html"))
        csv_files  = list(tmp_path.glob("doe_design_full2_*.csv"))
        assert len(html_files) == 1
        assert len(csv_files) == 1

    def test_tc_doe_des_002_full2_with_centre_points(self, tmp_path):
        """TC-DOE-DES-002: full2, 3 factors, 3 centre points → exit 0, total run count 11 in output"""
        r = run("jrc_doe_design.R", "full2", data("doe_factors_3f_2level.csv"),
                "SealStrength_N", str(tmp_path), "3")
        assert r.returncode == 0
        out = combined(r)
        assert "11" in out
        assert "3" in out

    def test_tc_doe_des_003_full2_with_replicates(self, tmp_path):
        """TC-DOE-DES-003: full2, 3 factors, 0 centre points, 2 replicates → exit 0, 16 runs in output"""
        r = run("jrc_doe_design.R", "full2", data("doe_factors_3f_2level.csv"),
                "SealStrength_N", str(tmp_path), "0", "2")
        assert r.returncode == 0
        assert "16" in combined(r)

    def test_tc_doe_des_004_full3_2factor(self, tmp_path):
        """TC-DOE-DES-004: full3, 2 factors → exit 0, HTML created, 9 runs in output"""
        r = run("jrc_doe_design.R", "full3", data("doe_factors_2f_3level.csv"),
                "SealStrength_N", str(tmp_path))
        assert r.returncode == 0
        html_files = list(tmp_path.glob("doe_design_full3_*.html"))
        assert len(html_files) == 1
        assert "9" in combined(r)

    def test_tc_doe_des_005_fractional_4factor(self, tmp_path):
        """TC-DOE-DES-005: fractional, 4 factors → exit 0, HTML and CSV created"""
        r = run("jrc_doe_design.R", "fractional", data("doe_factors_4f_2level.csv"),
                "SealStrength_N", str(tmp_path))
        assert r.returncode == 0
        html_files = list(tmp_path.glob("doe_design_fractional_*.html"))
        csv_files  = list(tmp_path.glob("doe_design_fractional_*.csv"))
        assert len(html_files) == 1
        assert len(csv_files) == 1

    def test_tc_doe_des_006_pb_6factor(self, tmp_path):
        """TC-DOE-DES-006: pb, 6 factors → exit 0, HTML created, 8 runs in output"""
        r = run("jrc_doe_design.R", "pb", data("doe_factors_6f.csv"),
                "Strength", str(tmp_path))
        assert r.returncode == 0
        html_files = list(tmp_path.glob("doe_design_pb_*.html"))
        assert len(html_files) == 1
        assert "8" in combined(r)

    def test_tc_doe_des_007_invalid_type(self, tmp_path):
        """TC-DOE-DES-007: invalid design type → non-zero exit, error mentions type or valid types"""
        r = run("jrc_doe_design.R", "badtype", data("doe_factors_3f_2level.csv"),
                "SealStrength_N", str(tmp_path))
        assert r.returncode != 0
        out = combined(r).lower()
        assert "badtype" in out or "invalid" in out or "full2" in out

    def test_tc_doe_des_008_factors_file_not_found(self, tmp_path):
        """TC-DOE-DES-008: nonexistent factors file → non-zero exit"""
        r = run("jrc_doe_design.R", "full2", "nonexistent_factors.csv",
                "SealStrength_N", str(tmp_path))
        assert r.returncode != 0

    def test_tc_doe_des_009_too_few_factors(self, tmp_path):
        """TC-DOE-DES-009: factors file with only 1 factor → non-zero exit, error mentions minimum"""
        r = run("jrc_doe_design.R", "full2", data("doe_factors_1f.csv"),
                "SealStrength_N", str(tmp_path))
        assert r.returncode != 0
        out = combined(r).lower()
        assert "2 factor" in out or "least 2" in out or "at least" in out or "factor" in out

    def test_tc_doe_des_010_missing_arguments(self, tmp_path):
        """TC-DOE-DES-010: only 3 arguments supplied → non-zero exit, usage in output"""
        r = run("jrc_doe_design.R", "full2", data("doe_factors_3f_2level.csv"),
                "SealStrength_N")
        assert r.returncode != 0
        assert "usage" in combined(r).lower()

    def test_tc_doe_des_011_html_content_check(self, tmp_path):
        """TC-DOE-DES-011: full2, 3 factors → HTML contains expected section headings and factor names"""
        r = run("jrc_doe_design.R", "full2", data("doe_factors_3f_2level.csv"),
                "SealStrength_N", str(tmp_path))
        assert r.returncode == 0
        html_files = list(tmp_path.glob("doe_design_full2_*.html"))
        assert len(html_files) == 1
        content = html_files[0].read_text()
        assert "Design Summary" in content
        assert "Temperature" in content
        assert "Pressure" in content
        assert "DwellTime" in content
        assert "SealStrength_N" in content

    def test_tc_doe_des_012_csv_comment_line(self, tmp_path):
        """TC-DOE-DES-012: full2, 3 factors → companion CSV first line is a valid jrc_doe_design comment"""
        r = run("jrc_doe_design.R", "full2", data("doe_factors_3f_2level.csv"),
                "SealStrength_N", str(tmp_path))
        assert r.returncode == 0
        csv_files = list(tmp_path.glob("doe_design_full2_*.csv"))
        assert len(csv_files) == 1
        first_line = csv_files[0].read_text().splitlines()[0]
        assert first_line.startswith("# jrc_doe_design:")
        assert "type=full2" in first_line
        assert "response=SealStrength_N" in first_line


# ===========================================================================
# jrc_doe_analyse (TC-DOE-ANA-001 .. 008)
# ===========================================================================

class TestDoeAnalyse:

    def test_tc_doe_ana_001_full2_basic(self, tmp_path):
        """TC-DOE-ANA-001: standard full2 analysis → exit 0, HTML report created"""
        r = run("jrc_doe_analyse.R", data("doe_results_full2_3f.csv"), str(tmp_path))
        assert r.returncode == 0
        html_files = list(tmp_path.glob("doe_analysis_*.html"))
        assert len(html_files) == 1
        out = combined(r).lower()
        assert "anova" in out or "analysis" in out

    def test_tc_doe_ana_002_significant_factor_detected(self, tmp_path):
        """TC-DOE-ANA-002: Temperature has large effect (+5 per coded unit) → mentioned in output"""
        r = run("jrc_doe_analyse.R", data("doe_results_full2_3f.csv"), str(tmp_path))
        assert r.returncode == 0
        assert "Temperature" in combined(r)

    def test_tc_doe_ana_003_centre_points_curvature_test(self, tmp_path):
        """TC-DOE-ANA-003: full2 with centre points → exit 0, curvature test performed"""
        r = run("jrc_doe_analyse.R", data("doe_results_full2_3f_cp.csv"), str(tmp_path))
        assert r.returncode == 0
        assert "curvature" in combined(r).lower()

    def test_tc_doe_ana_004_full3_analysis(self, tmp_path):
        """TC-DOE-ANA-004: full3 analysis with 2 factors → exit 0, HTML report created"""
        r = run("jrc_doe_analyse.R", data("doe_results_full3_2f.csv"), str(tmp_path))
        assert r.returncode == 0
        html_files = list(tmp_path.glob("doe_analysis_*.html"))
        assert len(html_files) == 1

    def test_tc_doe_ana_005_pb_analysis(self, tmp_path):
        """TC-DOE-ANA-005: Plackett-Burman analysis with 6 factors → exit 0, HTML report created"""
        r = run("jrc_doe_analyse.R", data("doe_results_pb_6f.csv"), str(tmp_path))
        assert r.returncode == 0
        html_files = list(tmp_path.glob("doe_analysis_*.html"))
        assert len(html_files) == 1

    def test_tc_doe_ana_006_missing_response_values(self, tmp_path):
        """TC-DOE-ANA-006: results file with empty response cells → non-zero exit, error mentions missing data"""
        r = run("jrc_doe_analyse.R", data("doe_results_missing_response.csv"), str(tmp_path))
        assert r.returncode != 0
        out = combined(r).lower()
        assert "missing" in out or "response" in out or "empty" in out

    def test_tc_doe_ana_007_file_not_found(self, tmp_path):
        """TC-DOE-ANA-007: nonexistent results file → non-zero exit"""
        r = run("jrc_doe_analyse.R", "nonexistent_results.csv", str(tmp_path))
        assert r.returncode != 0

    def test_tc_doe_ana_008_missing_arguments(self):
        """TC-DOE-ANA-008: only 1 argument supplied → non-zero exit, usage in output"""
        r = run("jrc_doe_analyse.R", data("doe_results_full2_3f.csv"))
        assert r.returncode != 0
        assert "usage" in combined(r).lower()


# ===========================================================================
# jrc_doe_design — boundary and validation tests (TC-DOE-DES-013 .. 018)
# ===========================================================================

class TestDoeDesignExtended:

    def test_tc_doe_des_013_full2_run_limit(self, tmp_path):
        """TC-DOE-DES-013: full2 with 9 factors → error (2^9=512 exceeds 256-run limit)"""
        r = run("jrc_doe_design.R", "full2", data("doe_factors_9f_2level.csv"),
                "Response", str(tmp_path))
        assert r.returncode != 0
        out = combined(r)
        assert "256" in out or "limit" in out.lower() or "exceeds" in out.lower()

    def test_tc_doe_des_014_full3_run_limit(self, tmp_path):
        """TC-DOE-DES-014: full3 with 6 factors → error (3^6=729 exceeds 243-run limit)"""
        r = run("jrc_doe_design.R", "full3", data("doe_factors_6f_3level.csv"),
                "Response", str(tmp_path))
        assert r.returncode != 0
        out = combined(r)
        assert "243" in out or "limit" in out.lower() or "exceeds" in out.lower()

    def test_tc_doe_des_015_invalid_centre_points(self, tmp_path):
        """TC-DOE-DES-015: centre_points = -1 → non-zero exit, error mentions centre_points"""
        r = run("jrc_doe_design.R", "full2", data("doe_factors_3f_2level.csv"),
                "SealStrength_N", str(tmp_path), "-1")
        assert r.returncode != 0
        out = combined(r).lower()
        assert "centre" in out or ">= 0" in out

    def test_tc_doe_des_016_invalid_replicates(self, tmp_path):
        """TC-DOE-DES-016: replicates = 0 → non-zero exit, error mentions replicates"""
        r = run("jrc_doe_design.R", "full2", data("doe_factors_3f_2level.csv"),
                "SealStrength_N", str(tmp_path), "0", "0")
        assert r.returncode != 0
        out = combined(r).lower()
        assert "replicate" in out or ">= 1" in out

    def test_tc_doe_des_017_centre_points_and_replicates_combined(self, tmp_path):
        """TC-DOE-DES-017: full2, 3 factors, 2 centre points, 2 replicates → exit 0, total runs = 18"""
        r = run("jrc_doe_design.R", "full2", data("doe_factors_3f_2level.csv"),
                "SealStrength_N", str(tmp_path), "2", "2")
        assert r.returncode == 0
        # 2^3 base × 2 replicates = 16 factorial + 2 centre = 18 total
        assert "18" in combined(r)
        html_files = list(tmp_path.glob("doe_design_full2_*.html"))
        csv_files  = list(tmp_path.glob("doe_design_full2_*.csv"))
        assert len(html_files) == 1
        assert len(csv_files) == 1

    def test_tc_doe_des_018_fractional_with_centre_points(self, tmp_path):
        """TC-DOE-DES-018: fractional, 4 factors, 2 centre points → exit 0, HTML and CSV created"""
        r = run("jrc_doe_design.R", "fractional", data("doe_factors_4f_2level.csv"),
                "SealStrength_N", str(tmp_path), "2")
        assert r.returncode == 0
        html_files = list(tmp_path.glob("doe_design_fractional_*.html"))
        csv_files  = list(tmp_path.glob("doe_design_fractional_*.csv"))
        assert len(html_files) == 1
        assert len(csv_files) == 1


# ===========================================================================
# jrc_doe_analyse — numerical correctness and edge cases (TC-DOE-ANA-009 .. 015)
# ===========================================================================

class TestDoeAnalyseExtended:

    def test_tc_doe_ana_009_known_r_squared(self, tmp_path):
        """TC-DOE-ANA-009: 2^3 design with analytically constructed response → R² ≥ 0.99 in output.

        Data: Strength = 100 + 15·Temperature_coded + 5·Pressure_coded + 1·DwellTime_coded
              + 1·(T·P·D)_coded. The 3-way term loads onto the 1-df residual of the
              6-term model. Analytically: SS_resid=8, SS_total=2016, R²=0.99603.
        """
        r = run("jrc_doe_analyse.R", data("doe_results_known_effects.csv"), str(tmp_path))
        assert r.returncode == 0
        out = combined(r)
        m = re.search(r"R\u00b2\s*:\s+([0-9]+\.[0-9]+)", out)
        assert m is not None, f"R\u00b2 value not found in terminal output. Output was:\n{out}"
        r_sq = float(m.group(1))
        assert r_sq >= 0.99, f"Expected R\u00b2 \u2265 0.99 (analytically 0.996), got {r_sq}"
        assert r_sq <= 1.0, f"R\u00b2 must be \u2264 1.0, got {r_sq}"

    def test_tc_doe_ana_010_significant_factor_identification(self, tmp_path):
        """TC-DOE-ANA-010: known-effect design → only Temperature listed as significant.

        Analytically: F_Temperature=225 (p≈0.043), F_Pressure=25 (p≈0.127),
        F_DwellTime=1 (p=0.500), all 2-way interactions F=0. Only Temperature
        crosses the α=0.05 threshold with 1 residual df.
        """
        r = run("jrc_doe_analyse.R", data("doe_results_known_effects.csv"), str(tmp_path))
        assert r.returncode == 0
        out = combined(r)
        m = re.search(r"Significant\s*:\s+(.+)", out)
        assert m is not None, f"'Significant:' line not found in output. Output was:\n{out}"
        sig_line = m.group(1).strip()
        assert "Temperature" in sig_line, \
            f"Temperature should be significant, got: '{sig_line}'"
        assert "Pressure" not in sig_line, \
            f"Pressure should NOT be significant (p≈0.127), got: '{sig_line}'"
        assert "DwellTime" not in sig_line, \
            f"DwellTime should NOT be significant (p=0.500), got: '{sig_line}'"

    def test_tc_doe_ana_011_r_squared_in_range(self, tmp_path):
        """TC-DOE-ANA-011: standard full2 analysis → R² reported in terminal is in [0, 1]"""
        r = run("jrc_doe_analyse.R", data("doe_results_full2_3f.csv"), str(tmp_path))
        assert r.returncode == 0
        out = combined(r)
        m = re.search(r"R\u00b2\s*:\s+([0-9]+\.[0-9]+)", out)
        assert m is not None, f"R\u00b2 value not found in terminal output. Output was:\n{out}"
        r_sq = float(m.group(1))
        assert 0.0 <= r_sq <= 1.0, f"R\u00b2 out of valid range [0, 1]: {r_sq}"

    def test_tc_doe_ana_012_curvature_significant(self, tmp_path):
        """TC-DOE-ANA-012: full2 with centre points far from factorial mean → curvature is significant.

        Data: factorial mean = 20.09, centre mean = 21.1 (3 points).
        Analytically: SS_curv≈2.24, MS_resid≈0.011, F≈199 → p << 0.001.
        """
        r = run("jrc_doe_analyse.R", data("doe_results_full2_3f_cp.csv"), str(tmp_path))
        assert r.returncode == 0
        out = combined(r).lower()
        m = re.search(r"curvature\s*:\s+(not significant|significant)", out)
        assert m is not None, f"Curvature verdict not found in output. Output was:\n{out}"
        assert m.group(1) == "significant", \
            f"Expected 'significant' curvature (p<<0.001), got: '{m.group(1)}'"

    def test_tc_doe_ana_013_curvature_not_significant(self, tmp_path):
        """TC-DOE-ANA-013: full2 with centre points near factorial mean → curvature is not significant.

        Data: factorial mean = 20.09, centre mean = 20.0 (3 points at 20.0).
        Analytically: SS_curv≈0.017, MS_resid≈0.011, F≈1.49 → p≈0.44.
        """
        r = run("jrc_doe_analyse.R", data("doe_results_no_curvature.csv"), str(tmp_path))
        assert r.returncode == 0
        out = combined(r).lower()
        m = re.search(r"curvature\s*:\s+(not significant|significant)", out)
        assert m is not None, f"Curvature verdict not found in output. Output was:\n{out}"
        assert m.group(1) == "not significant", \
            f"Expected 'not significant' curvature (p≈0.44), got: '{m.group(1)}'"

    def test_tc_doe_ana_014_constant_response(self, tmp_path):
        """TC-DOE-ANA-014: all response values identical (zero variance) → degenerate fit detected.

        With sigma_resid=0 the standardised effects are undefined (0/0).
        R detects this and issues an "essentially perfect fit" warning, which must
        appear in the output. Alternatively the script may error or produce NaN.
        In any case the output must not look like a clean, valid analysis.
        """
        r = run("jrc_doe_analyse.R", data("doe_results_constant_response.csv"), str(tmp_path))
        out = combined(r)
        has_issue = (
            "NaN" in out
            or "perfect fit" in out.lower()
            or "unreliable" in out.lower()
            or r.returncode != 0
        )
        assert has_issue, (
            "Constant response should produce non-zero exit, NaN, or an "
            "'essentially perfect fit' / 'unreliable' warning; "
            f"got returncode={r.returncode} with no such signal in output"
        )

    def test_tc_doe_ana_015_html_report_completeness(self, tmp_path):
        """TC-DOE-ANA-015: standard full2 analysis → HTML contains ANOVA table, embedded plots, no NaN.

        Base64 image payloads are stripped before the NaN/Inf check to avoid false
        positives from coincidental letter sequences in encoded binary data.
        """
        r = run("jrc_doe_analyse.R", data("doe_results_full2_3f.csv"), str(tmp_path))
        assert r.returncode == 0
        html_files = list(tmp_path.glob("doe_analysis_*.html"))
        assert len(html_files) == 1
        content = html_files[0].read_text()
        assert "ANOVA" in content, "HTML report missing ANOVA section"
        assert "Residuals" in content, "HTML report missing Residuals row in ANOVA table"
        assert "data:image/png;base64," in content, "HTML report missing embedded plot image(s)"
        # Strip base64 payloads before checking for degenerate numeric tokens
        content_no_b64 = re.sub(r'data:image/[^"\']+', '[IMAGE]', content)
        assert "NaN" not in content_no_b64, \
            "HTML report (outside image data) contains NaN — model fitting produced invalid results"
        assert "Inf" not in content_no_b64, \
            "HTML report (outside image data) contains Inf — model fitting produced invalid results"
