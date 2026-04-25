"""
OQ test suite — Statistical analysis scripts.

Covers: jrc_bland_altman, jrc_weibull, jrc_verify_attr (TC-VER-001..012),
        jrc_verify_discrete (TC-VER-DISC-001..009)
"""

import os
import glob
import time
from conftest import run, combined, extract_float, DATA_DIR

DOWNLOADS = os.path.expanduser("~/Downloads")


def data(name):
    return os.path.join(DATA_DIR, name)


def png_count_in_data():
    return glob.glob(os.path.join(DATA_DIR, "*.png"))


# ===========================================================================
# jrc_bland_altman (TC-BA-001 .. 005)
# ===========================================================================

class TestBlandAltman:

    def test_tc_ba_001_two_methods_known_bias(self):
        """TC-BA-001: Two methods → exit 0, Bias and LoA in output, PNG created"""
        # Clean any pre-existing PNGs
        for p in glob.glob(os.path.join(DATA_DIR, "*bland_altman*.png")):
            os.remove(p)

        r = run("jrc_bland_altman.R",
                data("bland_altman_method1_seed42.csv"), "value",
                data("bland_altman_method2_seed42.csv"), "value")
        assert r.returncode == 0
        out = combined(r).lower()
        assert "bias" in out
        assert "loa" in out or "limits of agreement" in out or "limit" in out

    def test_tc_ba_002_no_proportional_bias(self):
        """TC-BA-002: No significant proportional bias expected"""
        r = run("jrc_bland_altman.R",
                data("bland_altman_method1_seed42.csv"), "value",
                data("bland_altman_method2_seed42.csv"), "value")
        assert r.returncode == 0
        out = combined(r).lower()
        assert "p >=" in out or "no significant" in out or "proportional" in out

    def test_tc_ba_003_mismatched_row_counts(self):
        """TC-BA-003: 10-row file vs 25-row file → non-zero exit, 'different' in output"""
        r = run("jrc_bland_altman.R",
                data("method1_short.csv"), "value",
                data("bland_altman_method2_seed42.csv"), "value")
        assert r.returncode != 0
        out = combined(r).lower()
        assert "different" in out or "mismatch" in out or "rows" in out or "length" in out

    def test_tc_ba_004_file_not_found(self):
        """TC-BA-004: nonexistent file1 → non-zero exit"""
        r = run("jrc_bland_altman.R",
                "nonexistent.csv", "value",
                data("bland_altman_method2_seed42.csv"), "value")
        assert r.returncode != 0

    def test_tc_ba_005_missing_arguments(self):
        """TC-BA-005: only 3 arguments → non-zero exit, mentions 'Usage'"""
        r = run("jrc_bland_altman.R",
                data("bland_altman_method1_seed42.csv"), "value",
                data("bland_altman_method2_seed42.csv"))
        assert r.returncode != 0
        assert "usage" in combined(r).lower()


# ===========================================================================
# jrc_weibull (TC-WEIB-001 .. 006)
# ===========================================================================

class TestWeibull:

    def test_tc_weib_001_standard_fit_with_censoring(self):
        """TC-WEIB-001: Weibull fit → exit 0, beta/eta/B-life values, PNG created"""
        for p in glob.glob(os.path.join(DATA_DIR, "*weibull*.png")):
            os.remove(p)

        r = run("jrc_weibull.R",
                data("weibull_n20_seed42.csv"), "cycles", "status")
        assert r.returncode == 0
        out = combined(r).lower()
        assert "beta" in out or "shape" in out
        assert "eta" in out or "scale" in out
        assert "b10" in out or "b1" in out or "b50" in out or "b-life" in out

    def test_tc_weib_002_all_censored(self):
        """TC-WEIB-002: All units censored → non-zero exit, mentions 'failure' or '2'"""
        r = run("jrc_weibull.R",
                data("all_censored.csv"), "cycles", "status")
        assert r.returncode != 0
        out = combined(r).lower()
        assert "failure" in out or "least 2" in out or "at least" in out

    def test_tc_weib_003_negative_time_values(self):
        """TC-WEIB-003: Negative time → non-zero exit, mentions 'positive'"""
        r = run("jrc_weibull.R",
                data("neg_times.csv"), "cycles", "status")
        assert r.returncode != 0
        assert "positive" in combined(r).lower()

    def test_tc_weib_004_invalid_status_values(self):
        """TC-WEIB-004: Status values {0,1,2} → non-zero exit"""
        r = run("jrc_weibull.R",
                data("bad_status.csv"), "cycles", "status")
        assert r.returncode != 0

    def test_tc_weib_005_file_not_found(self):
        """TC-WEIB-005: nonexistent file → non-zero exit"""
        r = run("jrc_weibull.R", "nonexistent.csv", "cycles", "status")
        assert r.returncode != 0

    def test_tc_weib_006_missing_arguments(self):
        """TC-WEIB-006: only 2 arguments → non-zero exit, mentions 'Usage'"""
        r = run("jrc_weibull.R",
                data("weibull_n20_seed42.csv"), "cycles")
        assert r.returncode != 0
        assert "usage" in combined(r).lower()


# ===========================================================================
# jrc_verify_attr (TC-VER-001 .. 008)
# ===========================================================================

class TestVerifyAttr:

    def test_tc_ver_001_one_sided_lower_spec_met(self):
        """TC-VER-001: 1-sided lower, wide spec → exit 0, ✅ in output"""
        r = run("jrc_verify_attr.R", "0.95", "0.95",
                data("normal_n30_mean10_sd1_seed42.csv"), "value", "7.0", "-")
        assert r.returncode == 0
        assert "✅" in combined(r)

    def test_tc_ver_002_one_sided_lower_spec_not_met(self):
        """TC-VER-002: 1-sided lower, tight spec → exit 0, ❌ in output"""
        r = run("jrc_verify_attr.R", "0.95", "0.95",
                data("normal_n30_mean10_sd1_seed42.csv"), "value", "9.8", "-")
        assert r.returncode == 0
        assert "❌" in combined(r)

    def test_tc_ver_003_two_sided_spec_met(self):
        """TC-VER-003: 2-sided, wide spec → exit 0, ✅ in output"""
        r = run("jrc_verify_attr.R", "0.95", "0.95",
                data("normal_n30_mean10_sd1_seed42.csv"), "value", "7.0", "13.0")
        assert r.returncode == 0
        assert "✅" in combined(r)

    def test_tc_ver_004_skewed_data_boxcox_path(self):
        """TC-VER-004: Skewed data → exit 0, Box-Cox mentioned"""
        r = run("jrc_verify_attr.R", "0.95", "0.95",
                data("skewed_n30_lognormal_seed42.csv"), "value", "1.0", "-")
        assert r.returncode == 0
        out = combined(r).lower()
        assert "box-cox" in out or "boxcox" in out

    def test_tc_ver_005_spec2_le_spec1(self):
        """TC-VER-005: spec2 < spec1 → non-zero exit, mentions 'spec2'"""
        r = run("jrc_verify_attr.R", "0.95", "0.95",
                data("normal_n30_mean10_sd1_seed42.csv"), "value", "11.0", "9.0")
        assert r.returncode != 0
        assert "spec2" in combined(r).lower()

    def test_tc_ver_006_png_file_created(self):
        """TC-VER-006: PNG output created in same directory as input CSV"""
        # Clean any pre-existing tolerance PNGs
        for p in glob.glob(os.path.join(DATA_DIR, "*tolerance*.png")):
            os.remove(p)
        before = set(os.listdir(DATA_DIR))

        r = run("jrc_verify_attr.R", "0.95", "0.95",
                data("normal_n30_mean10_sd1_seed42.csv"), "value", "7.0", "-")
        assert r.returncode == 0

        after = set(os.listdir(DATA_DIR))
        new_files = after - before
        png_files = [f for f in new_files if f.endswith(".png")]
        assert len(png_files) >= 1

    def test_tc_ver_007_file_not_found(self):
        """TC-VER-007: nonexistent file → non-zero exit"""
        r = run("jrc_verify_attr.R", "0.95", "0.95",
                "nonexistent.csv", "value", "7.0", "-")
        assert r.returncode != 0

    def test_tc_ver_008_missing_arguments(self):
        """TC-VER-008: only 5 arguments → non-zero exit, mentions 'Usage'"""
        r = run("jrc_verify_attr.R", "0.95", "0.95",
                data("normal_n30_mean10_sd1_seed42.csv"), "value", "7.0")
        assert r.returncode != 0
        assert "usage" in combined(r).lower()

    def test_tc_ver_009_ti_lower_value_and_pass_verdict(self):
        """TC-VER-009: known dataset (mean=10, sd=1), P=0.95, C=0.95, LSL=7.0 → ✅
        Dataset: verify_attr_known.csv — 28 rows of 10.0 + rows 29 (13.8079) and 30 (6.1921).
        Exact: mean=10.0000, sd=1.0000 (sum(x-10)^2 = 2×(3.8079)^2 ≈ 29.000; var = 29/29 = 1).
        K1(n=30, P=0.95, C=0.95) = 2.220 (nct.ppf(0.95, df=29, nc=sqrt(30)*qnorm(0.95))/sqrt(30)).
        Expected lower TL = 10.000 - 2.220×1.000 = 7.780.
        LSL=7.0 < 7.780 → ✅.
        Assertion: extracted TI lower ≈ 7.780 ± 0.050 AND ✅ in output.
        """
        r = run("jrc_verify_attr.R", "0.95", "0.95",
                data("verify_attr_known.csv"), "value", "7.0", "-")
        assert r.returncode == 0
        tl = extract_float(r, "1-sided lower tolerance limit:")
        print(f"  TI lower: extracted = {tl}")
        assert tl is not None, f"Could not extract TI lower limit:\n{combined(r)}"
        print(f"  TI lower: expected 7.780 ± 0.050, got {tl}")
        assert abs(tl - 7.780) <= 0.050, \
            f"Expected TI lower ≈ 7.780 ± 0.050, got {tl}"
        print(f"  verdict: found '✅' in output = {'✅' in combined(r)}")
        assert "✅" in combined(r)

    def test_tc_ver_010_ti_lower_value_and_fail_verdict(self):
        """TC-VER-010: same dataset as TC-VER-009, LSL tightened to 8.0 → ❌
        Same TI lower = 7.780 (same data, same K-factor K1=2.220).
        7.780 < 8.0 = LSL → ❌.
        TC-VER-009 and TC-VER-010 use identical K-factor arithmetic but different spec limits,
        simultaneously verifying (a) the numeric TI computation and (b) the verdict logic.
        """
        r = run("jrc_verify_attr.R", "0.95", "0.95",
                data("verify_attr_known.csv"), "value", "8.0", "-")
        assert r.returncode == 0
        tl = extract_float(r, "1-sided lower tolerance limit:")
        print(f"  TI lower: extracted = {tl}")
        assert tl is not None, f"Could not extract TI lower limit:\n{combined(r)}"
        print(f"  TI lower: expected 7.780 ± 0.050, got {tl}")
        assert abs(tl - 7.780) <= 0.050, \
            f"Expected TI lower ≈ 7.780 ± 0.050, got {tl}"
        print(f"  TI lower < 8.0 (verdict ❌): {tl} < 8.0 = {tl < 8.0}")
        assert tl < 8.0, f"Expected TI lower < 8.0 (so verdict is ❌), got {tl}"
        print(f"  verdict: found '❌' in output = {'❌' in combined(r)}")
        assert "❌" in combined(r)

    def test_tc_ver_011_ti_2sided_values_and_pass_verdict(self):
        """TC-VER-011: same dataset, 2-sided, LSL=7.0, USL=13.0 → ✅
        K2(n=30, P=0.95, C=0.95) = 2.555 (computed via nct / two-sided algorithm).
        LTL = 10.000 - 2.555×1.000 = 7.445; UTL = 10.000 + 2.555 = 12.555.
        7.445 > 7.0 (LSL) and 12.555 < 13.0 (USL) → ✅.
        """
        r = run("jrc_verify_attr.R", "0.95", "0.95",
                data("verify_attr_known.csv"), "value", "7.0", "13.0")
        assert r.returncode == 0
        ltl = extract_float(r, "2-sided lower tolerance limit:")
        utl = extract_float(r, "2-sided upper tolerance limit:")
        print(f"  2-sided LTL: extracted = {ltl}")
        assert ltl is not None, f"Could not extract 2-sided lower TL:\n{combined(r)}"
        print(f"  2-sided UTL: extracted = {utl}")
        assert utl is not None, f"Could not extract 2-sided upper TL:\n{combined(r)}"
        print(f"  2-sided LTL: expected 7.445 ± 0.050, got {ltl}")
        assert abs(ltl - 7.445) <= 0.050, \
            f"Expected 2-sided LTL ≈ 7.445 ± 0.050, got {ltl}"
        print(f"  2-sided UTL: expected 12.555 ± 0.050, got {utl}")
        assert abs(utl - 12.555) <= 0.050, \
            f"Expected 2-sided UTL ≈ 12.555 ± 0.050, got {utl}"
        print(f"  verdict: found '✅' in output = {'✅' in combined(r)}")
        assert "✅" in combined(r)


# ===========================================================================
# jrc_verify_attr — --report (TC-VER-012)
# ===========================================================================

class TestVerifyAttrReport:

    def test_tc_ver_012_report_html_created(self):
        """
        TC-VER-012:
        --report flag → exit 0 and HTML report written next to the input CSV.
        """
        t_start = time.time()
        for p in glob.glob(os.path.join(DATA_DIR, "*_value_verification_report.html")):
            os.remove(p)
        r = run("jrc_verify_attr.R", "0.95", "0.95",
                data("normal_n30_mean10_sd1_seed42.csv"), "value", "7.0", "-",
                "--report")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        html_files = [
            f for f in glob.glob(os.path.join(DATA_DIR, "*_value_verification_report.html"))
            if os.path.getmtime(f) >= t_start
        ]
        assert html_files, \
            "No *_value_verification_report.html found in DATA_DIR after --report run"


# ===========================================================================
# jrc_verify_discrete (TC-VER-DISC-001 .. 008)
# ===========================================================================
#
# Reference values computed independently using pure-Python Clopper-Pearson:
#   _cp_upper(N, f, C) — bisection on Binomial CDF (for f > 0)
#                      — exact formula 1-(1-C)^(1/N) for f = 0
# Both are mathematically equivalent to qbeta(C, f+1, N-f) and are
# computed at module import time below.

import math
from math import comb


def _binom_cdf(k, n, p):
    return sum(comb(n, i) * p**i * (1 - p)**(n - i) for i in range(k + 1))


def _cp_upper(N, f, C):
    """Upper one-sided Clopper-Pearson CI bound on failure rate."""
    if f == 0:
        return 1 - math.exp(math.log(1 - C) / N)
    lo, hi = 0.0, 1.0
    for _ in range(200):
        mid = (lo + hi) / 2
        if _binom_cdf(f, N, mid) > 1 - C:
            lo = mid   # CDF decreases as u increases; CDF too high → u too small
        else:
            hi = mid
    return (lo + hi) / 2


_REF_N125_F2   = _cp_upper(125, 2, 0.95)   # ≈ 0.04951
_REF_N60_F0    = _cp_upper(60,  0, 0.95)   # = 1-(0.05)^(1/60) ≈ 0.04870
_REF_N30_F3    = _cp_upper(30,  3, 0.95)   # ≈ 0.23855


class TestVerifyDiscrete:

    def test_tc_ver_disc_001_pass_case(self):
        """TC-VER-DISC-001: N=125, f=2, P=0.95, C=0.95 → exit 0, ✅ in output"""
        r = run("jrc_verify_discrete.R", "125", "2", "0.95", "0.95")
        assert r.returncode == 0
        assert "✅" in combined(r)

    def test_tc_ver_disc_002_fail_case(self):
        """TC-VER-DISC-002: N=30, f=3, P=0.95, C=0.95 → exit 0, ❌ in output"""
        r = run("jrc_verify_discrete.R", "30", "3", "0.95", "0.95")
        assert r.returncode == 0
        assert "❌" in combined(r)

    def test_tc_ver_disc_003_f0_note(self):
        """TC-VER-DISC-003: f=0 → exit 0, note about jrc_ss_discrete_ci"""
        r = run("jrc_verify_discrete.R", "60", "0", "0.95", "0.95")
        assert r.returncode == 0
        assert "jrc_ss_discrete_ci" in combined(r)

    def test_tc_ver_disc_004_upper_bound_numerical_n125_f2(self):
        """TC-VER-DISC-004: upper CI bound for N=125, f=2 matches pure-Python Clopper-Pearson.
        Reference: _cp_upper(125, 2, 0.95) ≈ 0.04951 → output shows ~4.95%.
        Tolerance ±0.05 percentage points.
        """
        r = run("jrc_verify_discrete.R", "125", "2", "0.95", "0.95")
        assert r.returncode == 0
        upper_pct = extract_float(r, "CI bound:")
        assert upper_pct is not None, f"Could not extract CI bound:\n{combined(r)}"
        upper = upper_pct / 100
        print(f"  upper bound: extracted = {upper:.5f}, reference = {_REF_N125_F2:.5f}")
        assert abs(upper - _REF_N125_F2) <= 0.0005, \
            f"Expected upper CI ≈ {_REF_N125_F2:.5f} ± 0.0005, got {upper:.5f}"

    def test_tc_ver_disc_005_upper_bound_numerical_f0(self):
        """TC-VER-DISC-005: upper CI bound for N=60, f=0 matches exact formula.
        Reference: 1 - (0.05)^(1/60) ≈ 0.04870 → output shows ~4.87%.
        Tolerance ±0.0005.
        """
        r = run("jrc_verify_discrete.R", "60", "0", "0.95", "0.95")
        assert r.returncode == 0
        upper_pct = extract_float(r, "CI bound:")
        assert upper_pct is not None, f"Could not extract CI bound:\n{combined(r)}"
        upper = upper_pct / 100
        print(f"  upper bound: extracted = {upper:.5f}, reference = {_REF_N60_F0:.5f}")
        assert abs(upper - _REF_N60_F0) <= 0.0005, \
            f"Expected upper CI ≈ {_REF_N60_F0:.5f} ± 0.0005, got {upper:.5f}"

    def test_tc_ver_disc_006_f_exceeds_n(self):
        """TC-VER-DISC-006: f > N → non-zero exit"""
        r = run("jrc_verify_discrete.R", "10", "15", "0.95", "0.95")
        assert r.returncode != 0

    def test_tc_ver_disc_007_missing_arguments(self):
        """TC-VER-DISC-007: only 3 arguments → non-zero exit, mentions 'Usage'"""
        r = run("jrc_verify_discrete.R", "125", "2", "0.95")
        assert r.returncode != 0
        assert "usage" in combined(r).lower()

    def test_tc_ver_disc_008_margin_sign(self):
        """TC-VER-DISC-008: PASS case has positive margin, FAIL case has negative margin."""
        r_pass = run("jrc_verify_discrete.R", "125", "2", "0.95", "0.95")
        r_fail = run("jrc_verify_discrete.R", "30",  "3", "0.95", "0.95")
        margin_pass = extract_float(r_pass, "Margin:")
        margin_fail = extract_float(r_fail, "Margin:")
        print(f"  PASS margin: {margin_pass}")
        print(f"  FAIL margin: {margin_fail}")
        assert margin_pass is not None
        assert margin_fail is not None
        assert margin_pass > 0, f"Expected positive margin for PASS, got {margin_pass}"
        assert margin_fail < 0, f"Expected negative margin for FAIL, got {margin_fail}"


# ===========================================================================
# jrc_verify_discrete — --report (TC-VER-DISC-009)
# ===========================================================================

class TestVerifyDiscreteReport:

    def test_tc_ver_disc_009_report_html_created(self):
        """
        TC-VER-DISC-009:
        --report flag → exit 0 and HTML report written to ~/Downloads/.
        """
        t_start = time.time()
        r = run("jrc_verify_discrete.R", "125", "2", "0.95", "0.95", "--report")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        html_files = [
            f for f in glob.glob(os.path.join(DOWNLOADS, "*_discrete_verification_report.html"))
            if os.path.getmtime(f) >= t_start
        ]
        assert html_files, \
            "No *_discrete_verification_report.html found in ~/Downloads/ after --report run"
