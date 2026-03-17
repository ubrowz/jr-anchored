"""
OQ test suite — Design of Experiments scripts.

Covers: jrc_doe_design (TC-DOE-DES-001..012), jrc_doe_analyse (TC-DOE-ANA-001..008)
"""

import os
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
