"""
OQ test suite — Diagnostic scripts.

Covers: jrc_normality, jrc_outliers, jrc_capability, jrc_descriptive

Regression assertions (code review 2026-10):

  TC-NORM-006   Symmetric heavy-tailed data: SW/AD reject, but jrc_ss_attr rule (|skew| < 0.5) uses data as-is — stated
  TC-OUT-005    Grubbs is two-sided: spike with one-sided p 0.037 / two-sided p 0.074 → not flagged
"""
import sys

# Force UTF-8 stdout/stderr on Windows (cp1252 cannot encode emoji)
if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if sys.stderr.encoding and sys.stderr.encoding.lower() != "utf-8":
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

import os
from conftest import run, combined, DATA_DIR


def data(name):
    return os.path.join(DATA_DIR, name)


# ===========================================================================
# jrc_normality (TC-NORM-001 .. 005)
# ===========================================================================

class TestNormality:

    def test_tc_norm_001_normal_data_normal_verdict(self):
        """TC-NORM-001: Normal data → exit 0, 'normal' in output and ✅"""
        r = run("jrc_normality.R",
                data("normal_n30_mean10_sd1_seed42.csv"), "value")
        assert r.returncode == 0
        out = combined(r).lower()
        assert "normal" in out

    def test_tc_norm_002_skewed_data_nonnormal(self):
        """TC-NORM-002: Skewed data → exit 0, Box-Cox or non-normal mentioned"""
        r = run("jrc_normality.R",
                data("skewed_n30_lognormal_seed42.csv"), "value")
        assert r.returncode == 0
        out = combined(r).lower()
        assert "box-cox" in out or "not normal" in out or "boxcox" in out or "non-normal" in out

    def test_tc_norm_003_file_not_found(self):
        """TC-NORM-003: nonexistent file → non-zero exit, mentions 'not found'"""
        r = run("jrc_normality.R", "nonexistent.csv", "value")
        assert r.returncode != 0
        assert "not found" in combined(r).lower()

    def test_tc_norm_004_column_not_found(self):
        """TC-NORM-004: bad column → non-zero exit"""
        r = run("jrc_normality.R",
                data("normal_n30_mean10_sd1_seed42.csv"), "badcol")
        assert r.returncode != 0
        out = combined(r).lower()
        assert "not found" in out or "available" in out

    def test_tc_norm_005_missing_arguments(self):
        """TC-NORM-005: only 1 argument → non-zero exit, mentions 'Usage'"""
        r = run("jrc_normality.R",
                data("normal_n30_mean10_sd1_seed42.csv"))
        assert r.returncode != 0
        assert "usage" in combined(r).lower()


# ===========================================================================
# jrc_outliers (TC-OUT-001 .. 004)
# ===========================================================================

class TestOutliers:

    def test_tc_out_001_no_outliers_clean_data(self):
        """TC-OUT-001: Clean data → exit 0, no outliers flagged"""
        r = run("jrc_outliers.R",
                data("normal_n30_mean10_sd1_seed42.csv"), "value")
        assert r.returncode == 0
        out = combined(r).lower()
        assert "no outlier" in out or "0 outlier" in out or "none" in out

    def test_tc_out_002_outlier_detected_in_spiked_data(self):
        """TC-OUT-002: Spiked data → exit 0, row 15 flagged"""
        r = run("jrc_outliers.R",
                data("outlier_n30_seed42.csv"), "value")
        assert r.returncode == 0
        out = combined(r)
        # row 15 is the injected outlier
        assert "15" in out

    def test_tc_out_003_file_not_found(self):
        """TC-OUT-003: nonexistent file → non-zero exit"""
        r = run("jrc_outliers.R", "nonexistent.csv", "value")
        assert r.returncode != 0

    def test_tc_out_004_missing_arguments(self):
        """TC-OUT-004: only 1 argument → non-zero exit, mentions 'Usage'"""
        r = run("jrc_outliers.R",
                data("normal_n30_mean10_sd1_seed42.csv"))
        assert r.returncode != 0
        assert "usage" in combined(r).lower()


# ===========================================================================
# jrc_capability (TC-CAP-001 .. 004)
# ===========================================================================

class TestCapability:

    def test_tc_cap_001_two_sided_capable_process(self):
        """TC-CAP-001: 2-sided, wide spec → exit 0, Cp Cpk Pp Ppk in output"""
        r = run("jrc_capability.R",
                data("normal_n30_mean10_sd1_seed42.csv"), "value", "7.0", "13.0")
        assert r.returncode == 0
        out = combined(r)
        assert "Cp" in out
        assert "Cpk" in out

    def test_tc_cap_002_one_sided_upper(self):
        """TC-CAP-002: 1-sided upper → exit 0"""
        r = run("jrc_capability.R",
                data("normal_n30_mean10_sd1_seed42.csv"), "value", "-", "13.0")
        assert r.returncode == 0

    def test_tc_cap_003_both_specs_absent(self):
        """TC-CAP-003: both '-' → non-zero exit"""
        r = run("jrc_capability.R",
                data("normal_n30_mean10_sd1_seed42.csv"), "value", "-", "-")
        assert r.returncode != 0

    def test_tc_cap_004_file_not_found(self):
        """TC-CAP-004: nonexistent file → non-zero exit"""
        r = run("jrc_capability.R", "nonexistent.csv", "value", "7.0", "13.0")
        assert r.returncode != 0


# ===========================================================================
# jrc_descriptive (TC-DESC-001 .. 004)
# ===========================================================================

class TestDescriptive:

    def test_tc_desc_001_normal_dataset(self):
        """TC-DESC-001: Standard data → exit 0, summary stats in output"""
        r = run("jrc_descriptive.R",
                data("normal_n30_mean10_sd1_seed42.csv"), "value")
        assert r.returncode == 0
        out = combined(r).lower()
        assert "mean" in out
        assert "sd" in out or "standard deviation" in out or "std" in out

    def test_tc_desc_002_file_not_found(self):
        """TC-DESC-002: nonexistent file → non-zero exit, mentions 'not found'"""
        r = run("jrc_descriptive.R", "nonexistent.csv", "value")
        assert r.returncode != 0
        assert "not found" in combined(r).lower()

    def test_tc_desc_003_column_not_found(self):
        """TC-DESC-003: bad column → non-zero exit"""
        r = run("jrc_descriptive.R",
                data("normal_n30_mean10_sd1_seed42.csv"), "badcol")
        assert r.returncode != 0

    def test_tc_desc_004_missing_arguments(self):
        """TC-DESC-004: only 1 argument → non-zero exit, mentions 'Usage'"""
        r = run("jrc_descriptive.R",
                data("normal_n30_mean10_sd1_seed42.csv"))
        assert r.returncode != 0
        assert "usage" in combined(r).lower()


class TestDiagnosticRegression:

    def test_tc_norm_006_symmetric_heavy_tails_prediction(self):
        """TC-NORM-006: code review 2026-10, COR-14. normality_symmetric_heavy.csv is
        mirrored t(2) data (skewness 0, heavy tails): Shapiro-Wilk rejects normality,
        but jrc_ss_attr & co. decide on |skewness| < 0.5 and use the data as-is. The
        script must say so (it used to predict a Box-Cox transformation)."""
        r = run("jrc_normality.R", data("normality_symmetric_heavy.csv"), "value")
        out = combined(r)
        assert r.returncode == 0, out
        assert "departures from normality" in out, out
        assert "They will use the data as-is (no transformation)." in out, out
        assert "are NOT acted upon" in out, out
        assert "Box-Cox transformation attempt" not in out, out

    def test_tc_out_005_grubbs_two_sided(self):
        """TC-OUT-005: code review 2026-10, COR-17. outliers_grubbs_borderline.csv:
        19 normal scores + 10 and a spike of 13.4. Independent reference
        (outliers::grubbs.test, type 10): one-sided p = 0.0368, two-sided p = 0.0737.
        The test of the most extreme value in either direction is two-sided, so at
        alpha = 0.05 the spike must NOT be flagged (it was before the fix)."""
        r = run("jrc_outliers.R", data("outliers_grubbs_borderline.csv"), "value")
        out = combined(r)
        assert r.returncode == 0, out
        assert "two-sided, alpha = 0.05" in out, out
        assert "0.0737" in out, out
        assert "Grubbs: no outliers detected." in out, out
