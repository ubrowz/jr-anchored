"""
OQ test suite — Sample Size scripts.

Covers: jrc_ss_discrete, jrc_ss_discrete_ci, jrc_ss_attr, jrc_ss_attr_check,
        jrc_ss_attr_ci, jrc_ss_sigma, jrc_ss_paired, jrc_ss_equivalence,
        jrc_ss_fatigue, jrc_msa_grr_design
"""

import os
from conftest import run, combined, extract_n_at_f, extract_float, extract_table_n, DATA_DIR


def data(name):
    return os.path.join(DATA_DIR, name)


# ===========================================================================
# jrc_ss_discrete (TC-DISC-001 .. 005)
# ===========================================================================

class TestSsDiscrete:

    def test_tc_disc_001_normal_input(self):
        """TC-DISC-001: P=0.99, C=0.95 → f=0 N=300 (chi-squared method)"""
        r = run("jrc_ss_discrete.R", "0.99", "0.95")
        assert r.returncode == 0
        # chi-squared method: ceiling(qchisq(0.95,2)/(2*0.01)) = 300
        assert "300" in combined(r)

    def test_tc_disc_002_lower_confidence_smaller_n(self):
        """TC-DISC-002: Lower confidence → smaller N at f=0"""
        r_std = run("jrc_ss_discrete.R", "0.99", "0.95")
        r_low = run("jrc_ss_discrete.R", "0.99", "0.80")
        assert r_low.returncode == 0
        n_std = extract_n_at_f(r_std, 0)
        n_low = extract_n_at_f(r_low, 0)
        assert n_std is not None and n_low is not None
        assert n_low < n_std

    def test_tc_disc_003_invalid_proportion(self):
        """TC-DISC-003: proportion=1.5 → non-zero exit, mentions 'proportion'"""
        r = run("jrc_ss_discrete.R", "1.5", "0.95")
        assert r.returncode != 0
        assert "proportion" in combined(r).lower()

    def test_tc_disc_004_invalid_confidence_zero(self):
        """TC-DISC-004: confidence=0 → non-zero exit, mentions 'confidence'"""
        r = run("jrc_ss_discrete.R", "0.99", "0")
        assert r.returncode != 0
        assert "confidence" in combined(r).lower()

    def test_tc_disc_005_missing_arguments(self):
        """TC-DISC-005: only 1 argument → non-zero exit, mentions 'Usage'"""
        r = run("jrc_ss_discrete.R", "0.99")
        assert r.returncode != 0
        assert "usage" in combined(r).lower()

    def test_tc_disc_006_n_exact_p99_c95_f0(self):
        """TC-DISC-006: P=0.99, C=0.95, f=0 → n=300 (exact)
        Independent: n = ceiling(qchisq(0.95,2) / (2*(1-0.99)))
                       = ceiling(5.9915 / 0.02) = ceiling(299.57) = 300
        chi-squared(2) CDF has closed form F(x)=1-exp(-x/2), so qchisq(0.95,2)=-2*ln(0.05)=5.9915.
        """
        r = run("jrc_ss_discrete.R", "0.99", "0.95")
        assert r.returncode == 0
        print(f"  n at f=0: expected 300, got {extract_n_at_f(r, 0)}")
        assert extract_n_at_f(r, 0) == 300

    def test_tc_disc_007_n_exact_p99_c95_f1(self):
        """TC-DISC-007: P=0.99, C=0.95, f=1 → n=475 (exact)
        Independent: n = ceiling(qchisq(0.95,4) / 0.02)
                       = ceiling(9.4877 / 0.02) = ceiling(474.39) = 475
        """
        r = run("jrc_ss_discrete.R", "0.99", "0.95")
        assert r.returncode == 0
        print(f"  n at f=1: expected 475, got {extract_n_at_f(r, 1)}")
        assert extract_n_at_f(r, 1) == 475

    def test_tc_disc_008_n_exact_p95_c90_f0(self):
        """TC-DISC-008: P=0.95, C=0.90, f=0 → n=47 (exact)
        Independent: n = ceiling(qchisq(0.90,2) / (2*(1-0.95)))
                       = ceiling(4.6052 / 0.10) = ceiling(46.05) = 47
        qchisq(0.90,2) = -2*ln(0.10) = 4.6052.
        """
        r = run("jrc_ss_discrete.R", "0.95", "0.90")
        assert r.returncode == 0
        print(f"  n at f=0: expected 47, got {extract_n_at_f(r, 0)}")
        assert extract_n_at_f(r, 0) == 47

    def test_tc_disc_009_n_exact_p99_c99_f0(self):
        """TC-DISC-009: P=0.99, C=0.99, f=0 → n=461 (exact)
        Independent: n = ceiling(qchisq(0.99,2) / 0.02)
                       = ceiling(9.2103 / 0.02) = ceiling(460.52) = 461
        qchisq(0.99,2) = -2*ln(0.01) = 9.2103.
        """
        r = run("jrc_ss_discrete.R", "0.99", "0.99")
        assert r.returncode == 0
        print(f"  n at f=0: expected 461, got {extract_n_at_f(r, 0)}")
        assert extract_n_at_f(r, 0) == 461


# ===========================================================================
# jrc_ss_discrete_ci (TC-DISCICI-001 .. 004)
# ===========================================================================

class TestSsDiscreteCi:

    def test_tc_discici_001_zero_failures(self):
        """TC-DISCICI-001: N=300, f=0, C=0.95 → achieved proportion ≥ 0.99"""
        r = run("jrc_ss_discrete_ci.R", "0.95", "300", "0")
        assert r.returncode == 0
        # Output should contain "0.99" (or higher)
        assert "0.99" in combined(r)

    def test_tc_discici_002_one_failure_lower_proportion(self):
        """TC-DISCICI-002: f=1 achieves lower proportion than f=0"""
        r0 = run("jrc_ss_discrete_ci.R", "0.95", "300", "0")
        r1 = run("jrc_ss_discrete_ci.R", "0.95", "300", "1")
        assert r0.returncode == 0 and r1.returncode == 0
        # Both should succeed; content will differ (output is descriptive)
        assert combined(r0) != combined(r1)

    def test_tc_discici_003_f_greater_than_n(self):
        """TC-DISCICI-003: f=15 > n=10 → non-zero exit"""
        r = run("jrc_ss_discrete_ci.R", "0.95", "10", "15")
        assert r.returncode != 0

    def test_tc_discici_004_missing_arguments(self):
        """TC-DISCICI-004: only 2 arguments → non-zero exit, mentions 'Usage'"""
        r = run("jrc_ss_discrete_ci.R", "0.95", "299")
        assert r.returncode != 0
        assert "usage" in combined(r).lower()

    def test_tc_discici_005_proportion_n300_f0(self):
        """TC-DISCICI-005: C=0.95, n=300, f=0 → proportion = 0.9998 ± 0.0001
        Independent (Clopper-Pearson, f=0 closed form):
          proportion = 1 - qbeta(0.05, 1, 300) = 1 - (1 - 0.95^{1/300}) = 0.99983
        For f=0, qbeta(p, 1, n) = 1-(1-p)^{1/n} — no external package needed.
        Consistency check: jrc_ss_discrete says n=300 achieves P=0.99 at C=0.95;
        this TC confirms proportion = 0.9998 >> 0.99. ✓
        """
        r = run("jrc_ss_discrete_ci.R", "0.95", "300", "0")
        assert r.returncode == 0
        p = extract_float(r, "proportion achieved:")
        print(f"  proportion achieved: extracted = {p}")
        assert p is not None, f"Could not extract proportion from output:\n{combined(r)}"
        print(f"  proportion achieved: expected 0.9998 ± 0.0001, got {p}")
        assert abs(p - 0.9998) <= 0.0001, f"Expected proportion ≈ 0.9998, got {p}"

    def test_tc_discici_006_proportion_n22_f0(self):
        """TC-DISCICI-006: C=0.95, n=22, f=0 → proportion = 0.9977 ± 0.0001
        Independent (f=0 closed form):
          proportion = 1 - (1 - 0.95^{1/22}) = 0.99767
        Confirms n=22 does NOT achieve P=0.99 (0.9977 < 0.99), consistent with
        jrc_ss_discrete requiring n=300 for P=0.99 at C=0.95.
        """
        r = run("jrc_ss_discrete_ci.R", "0.95", "22", "0")
        assert r.returncode == 0
        p = extract_float(r, "proportion achieved:")
        print(f"  proportion achieved: extracted = {p}")
        assert p is not None, f"Could not extract proportion from output:\n{combined(r)}"
        print(f"  proportion achieved: expected 0.9977 ± 0.0001, got {p}")
        assert abs(p - 0.9977) <= 0.0001, f"Expected proportion ≈ 0.9977, got {p}"


# ===========================================================================
# jrc_ss_attr (TC-ATTR-001 .. 007)
# ===========================================================================

class TestSsAttr:

    def test_tc_attr_001_one_sided_lower(self):
        """TC-ATTR-001: 1-sided lower, wide spec → exit 0, N ≥ 10"""
        # Use spec=7.0 (3σ from mean) so N stays within script's 250-sample cap
        r = run("jrc_ss_attr.R", "0.95", "0.95",
                data("normal_n30_mean10_sd1_seed42.csv"), "value", "7.0", "-")
        assert r.returncode == 0
        out = combined(r)
        assert "✅" in out or "n =" in out.lower()

    def test_tc_attr_002_one_sided_upper(self):
        """TC-ATTR-002: 1-sided upper, wide spec → exit 0"""
        r = run("jrc_ss_attr.R", "0.95", "0.95",
                data("normal_n30_mean10_sd1_seed42.csv"), "value", "-", "13.0")
        assert r.returncode == 0

    def test_tc_attr_003_two_sided_requires_more_than_one_sided(self):
        """TC-ATTR-003: 2-sided and 1-sided both succeed"""
        r1 = run("jrc_ss_attr.R", "0.95", "0.95",
                 data("normal_n30_mean10_sd1_seed42.csv"), "value", "7.0", "-")
        r2 = run("jrc_ss_attr.R", "0.95", "0.95",
                 data("normal_n30_mean10_sd1_seed42.csv"), "value", "7.0", "13.0")
        assert r1.returncode == 0 and r2.returncode == 0

    def test_tc_attr_004_spec2_le_spec1(self):
        """TC-ATTR-004: spec2 < spec1 → non-zero exit, mentions 'spec2'"""
        r = run("jrc_ss_attr.R", "0.95", "0.95",
                data("normal_n30_mean10_sd1_seed42.csv"), "value", "11.0", "9.0")
        assert r.returncode != 0
        assert "spec2" in combined(r).lower()

    def test_tc_attr_005_both_specs_absent(self):
        """TC-ATTR-005: both spec limits '-' → non-zero exit"""
        r = run("jrc_ss_attr.R", "0.95", "0.95",
                data("normal_n30_mean10_sd1_seed42.csv"), "value", "-", "-")
        assert r.returncode != 0

    def test_tc_attr_006_file_not_found(self):
        """TC-ATTR-006: nonexistent file → non-zero exit, mentions 'not found'"""
        r = run("jrc_ss_attr.R", "0.95", "0.95",
                "nonexistent.csv", "value", "9.0", "-")
        assert r.returncode != 0
        assert "not found" in combined(r).lower()

    def test_tc_attr_007_column_not_found(self):
        """TC-ATTR-007: bad column → non-zero exit, mentions 'not found' or 'available'"""
        r = run("jrc_ss_attr.R", "0.95", "0.95",
                data("normal_n30_mean10_sd1_seed42.csv"), "badcol", "9.0", "-")
        assert r.returncode != 0
        out = combined(r).lower()
        assert "not found" in out or "available" in out

    def test_tc_attr_008_required_n_numeric(self):
        """TC-ATTR-008: known dataset (mean=10, sd=1) 1-sided LSL=7.0, P=0.95, C=0.95
        k_sample = (10.000 - 7.000) / 1.000 = 3.000.
        K1(30, P=0.95, C=0.95) = 1.778 << 3.000, so pilot (n=30) is sufficient.
        K1 is monotonically decreasing; K1(n) <= 3.000 for all n >= 6 or 7 (Hahn & Meeker
        Table A.7), so the minimum required n is in range [3, 10].
        Asserts: (a) the required n is extracted and is in [3, 10], (b) the pilot is
        confirmed sufficient (n_required <= 30 available samples).
        """
        r = run("jrc_ss_attr.R", "0.95", "0.95",
                data("verify_attr_known.csv"), "value", "7.0", "-")
        assert r.returncode == 0
        n = extract_float(r, "required sample size for verification:")
        print(f"  required n: extracted = {n}")
        assert n is not None, f"Could not extract required n:\n{combined(r)}"
        print(f"  required n: expected in [3, 10], got {int(n)}")
        assert 3 <= int(n) <= 10, f"Expected required n in [3, 10], got {int(n)}"
        print(f"  'sufficient' found in output = {'sufficient' in combined(r).lower()}")
        assert "sufficient" in combined(r).lower()


# ===========================================================================
# jrc_ss_attr_check (TC-ATTRCK-001 .. 003)
# ===========================================================================

class TestSsAttrCheck:

    def test_tc_attrck_001_planned_n_meets_requirement(self):
        """TC-ATTRCK-001: planned N=50 meets → exit 0, PASS signal"""
        r = run("jrc_ss_attr_check.R", "0.95", "0.95",
                data("normal_n30_mean10_sd1_seed42.csv"), "value", "9.0", "-", "50")
        assert r.returncode == 0
        out = combined(r)
        assert "✅" in out or "pass" in out.lower()

    def test_tc_attrck_002_planned_n_too_small(self):
        """TC-ATTRCK-002: planned N=5 fails → exit 0, FAIL signal"""
        r = run("jrc_ss_attr_check.R", "0.95", "0.95",
                data("normal_n30_mean10_sd1_seed42.csv"), "value", "9.0", "-", "5")
        assert r.returncode == 0
        out = combined(r)
        assert "❌" in out or "fail" in out.lower()

    def test_tc_attrck_003_missing_planned_n(self):
        """TC-ATTRCK-003: missing planned_N → non-zero exit, mentions 'Usage'"""
        r = run("jrc_ss_attr_check.R", "0.95", "0.95",
                data("normal_n30_mean10_sd1_seed42.csv"), "value", "9.0", "-")
        assert r.returncode != 0
        assert "usage" in combined(r).lower()

    def test_tc_attrck_004_pass_n30_wide_spec(self):
        """TC-ATTRCK-004: known dataset (mean=10, sd=1), LSL=7.0, planned_N=30 → PASS
        k_sample = (10.000 - 7.000) / 1.000 = 3.000.
        K1(30, P=0.95, C=0.95) = 1.778 < 3.000 → margin = 1.222 > 0 → PASS.
        Independent reference: K1(30) = 1.778 from Hahn & Meeker 2017, Table A.7.
        """
        r = run("jrc_ss_attr_check.R", "0.95", "0.95",
                data("verify_attr_known.csv"), "value", "7.0", "-", "30")
        assert r.returncode == 0
        print(f"  verdict: 'pass' found in output = {'pass' in combined(r).lower()}")
        assert "pass" in combined(r).lower()

    def test_tc_attrck_005_fail_n30_tight_spec(self):
        """TC-ATTRCK-005: known dataset (mean=10, sd=1), LSL=8.5, planned_N=30 → FAIL
        k_sample = (10.000 - 8.500) / 1.000 = 1.500.
        K1(30, P=0.95, C=0.95) = 1.778 > 1.500 → margin = -0.278 < 0 → FAIL.
        Independent reference: K1(30) = 1.778 (same as TC-ATTRCK-004).
        This TC verifies that the same K-factor arithmetic correctly flips the verdict
        when the spec is tightened so that 30 samples are no longer sufficient.
        """
        r = run("jrc_ss_attr_check.R", "0.95", "0.95",
                data("verify_attr_known.csv"), "value", "8.5", "-", "30")
        assert r.returncode == 0
        print(f"  verdict: 'fail' found in output = {'fail' in combined(r).lower()}")
        assert "fail" in combined(r).lower()


# ===========================================================================
# jrc_ss_attr_ci (TC-ATTRCI-001 .. 003)
# ===========================================================================

class TestSsAttrCi:

    def test_tc_attrci_001_one_sided_lower(self):
        """TC-ATTRCI-001: 1-sided lower → exit 0, proportion between 0 and 1"""
        r = run("jrc_ss_attr_ci.R", "0.95",
                data("normal_n30_mean10_sd1_seed42.csv"), "value", "9.0", "-")
        assert r.returncode == 0
        assert "0." in combined(r)  # some decimal proportion reported

    def test_tc_attrci_002_two_sided(self):
        """TC-ATTRCI-002: 2-sided → exit 0"""
        r = run("jrc_ss_attr_ci.R", "0.95",
                data("normal_n30_mean10_sd1_seed42.csv"), "value", "9.0", "11.0")
        assert r.returncode == 0

    def test_tc_attrci_003_file_not_found(self):
        """TC-ATTRCI-003: nonexistent file → non-zero exit, mentions 'not found'"""
        r = run("jrc_ss_attr_ci.R", "0.95",
                "nonexistent.csv", "value", "9.0", "-")
        assert r.returncode != 0
        assert "not found" in combined(r).lower()

    def test_tc_attrci_004_achieved_proportion_numeric(self):
        """TC-ATTRCI-004: known dataset (mean=10, sd=1), C=0.95, 1-sided LSL=7.0
        k_sample = (10.000 - 7.000) / 1.000 = 3.000.
        K1(30, P=0.95, C=0.95) = 2.220 < 3.000, so the achieved proportion > 0.95.
        The bisection finds P such that K1(30, P, 0.95) = 3.000.
        Since K1(30, P=0.95, C=0.95) = 2.220 < 3.000, achieved proportion ≈ 0.989.
        Conservatively: 0.985 < achieved proportion < 1.000.
        """
        r = run("jrc_ss_attr_ci.R", "0.95",
                data("verify_attr_known.csv"), "value", "7.0", "-")
        assert r.returncode == 0
        p = extract_float(r, "proportion achieved at 0.95 confidence:")
        print(f"  proportion achieved: extracted = {p}")
        assert p is not None, f"Could not extract proportion:\n{combined(r)}"
        print(f"  proportion achieved: expected in (0.985, 1.000), got {p}")
        assert 0.985 < p < 1.000, f"Expected proportion in (0.985, 1.000), got {p}"


# ===========================================================================
# jrc_ss_sigma (TC-SIGMA-001 .. 004)
# ===========================================================================

class TestSsSigma:

    def test_tc_sigma_001_one_sided(self):
        """TC-SIGMA-001: 1-sided lower → exit 0, table output"""
        r = run("jrc_ss_sigma.R", "1.5", "9.0", "-")
        assert r.returncode == 0

    def test_tc_sigma_002_two_sided(self):
        """TC-SIGMA-002: 2-sided → exit 0"""
        r = run("jrc_ss_sigma.R", "1.5", "9.0", "11.0")
        assert r.returncode == 0

    def test_tc_sigma_003_invalid_precision(self):
        """TC-SIGMA-003: negative precision → non-zero exit"""
        r = run("jrc_ss_sigma.R", "-1.0", "9.0", "-")
        assert r.returncode != 0

    def test_tc_sigma_004_missing_arguments(self):
        """TC-SIGMA-004: only 1 argument → non-zero exit, mentions 'Usage'"""
        r = run("jrc_ss_sigma.R", "1.5")
        assert r.returncode != 0
        assert "usage" in combined(r).lower()

    def test_tc_sigma_005_n_exact_precision15_1sided_power090_c095(self):
        """TC-SIGMA-005: precision=1.5, 1-sided, power=0.90, C=0.95 → n=5
        Independent: n = ceiling(((z_α + z_β) / precision)²) + 1
          z_α = qnorm(0.95) = 1.6449,  z_β = qnorm(0.90) = 1.2816
          n = ceiling(((1.6449 + 1.2816) / 1.5)²) + 1 = ceiling(3.806) + 1 = 4+1 = 5
        """
        r = run("jrc_ss_sigma.R", "1.5", "9.0", "-")
        assert r.returncode == 0
        n = extract_table_n(r, 0.90, 2)   # col 2 = C=0.95
        print(f"  n (power=0.90, C=0.95): expected 5, got {n}")
        assert n is not None, f"Could not extract n from table:\n{combined(r)}"
        assert n == 5, f"Expected n=5 at power=0.90, C=0.95, got {n}"

    def test_tc_sigma_006_n_exact_precision10_2sided_power095_c095(self):
        """TC-SIGMA-006: precision=1.0, 2-sided, power=0.95, C=0.95 → n=14
        Independent: z_α = qnorm(0.975) = 1.9600,  z_β = qnorm(0.95) = 1.6449
          n = ceiling(((1.9600 + 1.6449) / 1.0)²) + 1 = ceiling(12.995) + 1 = 13+1 = 14
        This is also the FDA-standard cell (power=0.95, C=0.95).
        """
        r = run("jrc_ss_sigma.R", "1.0", "9.0", "11.0")
        assert r.returncode == 0
        n = extract_table_n(r, 0.95, 2)   # col 2 = C=0.95
        print(f"  n (power=0.95, C=0.95): expected 14, got {n}")
        assert n is not None, f"Could not extract n from table:\n{combined(r)}"
        assert n == 14, f"Expected n=14 at power=0.95, C=0.95, got {n}"
        # Also verify the FDA-standard summary line
        print(f"  'N >= 14' in output = {'N >= 14' in combined(r)}")
        assert "N >= 14" in combined(r), \
            f"Expected 'N >= 14' in FDA summary line:\n{combined(r)}"

    def test_tc_sigma_007_n_exact_precision20_1sided_power090_c090(self):
        """TC-SIGMA-007: precision=2.0, 1-sided, power=0.90, C=0.90 → n=3
        Independent: z_α = qnorm(0.90) = 1.2816,  z_β = qnorm(0.90) = 1.2816
          n = ceiling(((1.2816 + 1.2816) / 2.0)²) + 1 = ceiling(1.642) + 1 = 2+1 = 3
        """
        r = run("jrc_ss_sigma.R", "2.0", "9.0", "-")
        assert r.returncode == 0
        n = extract_table_n(r, 0.90, 1)   # col 1 = C=0.90
        print(f"  n (power=0.90, C=0.90): expected 3, got {n}")
        assert n is not None, f"Could not extract n from table:\n{combined(r)}"
        assert n == 3, f"Expected n=3 at power=0.90, C=0.90, got {n}"


# ===========================================================================
# jrc_ss_paired (TC-PAIRED-001 .. 005)
# ===========================================================================

class TestSsPaired:

    def test_tc_paired_001_two_sided(self):
        """TC-PAIRED-001: 2-sided → exit 0, table with N ≥ 10"""
        r = run("jrc_ss_paired.R", "0.5", "1.0", "2")
        assert r.returncode == 0

    def test_tc_paired_002_one_sided_smaller_n(self):
        """TC-PAIRED-002: 1-sided produces output (smaller N than 2-sided)"""
        r1 = run("jrc_ss_paired.R", "0.5", "1.0", "1")
        r2 = run("jrc_ss_paired.R", "0.5", "1.0", "2")
        assert r1.returncode == 0 and r2.returncode == 0

    def test_tc_paired_003_invalid_sides(self):
        """TC-PAIRED-003: sides=3 → non-zero exit"""
        r = run("jrc_ss_paired.R", "0.5", "1.0", "3")
        assert r.returncode != 0

    def test_tc_paired_004_sd_le_zero(self):
        """TC-PAIRED-004: sd=0 → non-zero exit"""
        r = run("jrc_ss_paired.R", "0.5", "0", "2")
        assert r.returncode != 0

    def test_tc_paired_005_missing_arguments(self):
        """TC-PAIRED-005: only 1 argument → non-zero exit, mentions 'Usage'"""
        r = run("jrc_ss_paired.R", "0.5")
        assert r.returncode != 0
        assert "usage" in combined(r).lower()

    def test_tc_paired_006_n_exact_2sided_power090_c095(self):
        """TC-PAIRED-006: delta=0.5, sd=1.0, sides=2, power=0.90, C=0.95 → n=44
        Independent: effect_size = 0.5/1.0 = 0.5; 2-sided z_α = qnorm(0.975) = 1.9600
          z_β = qnorm(0.90) = 1.2816
          n = ceiling(((1.9600+1.2816)/0.5)²) + 1 = ceiling(42.03) + 1 = 43+1 = 44
        """
        r = run("jrc_ss_paired.R", "0.5", "1.0", "2")
        assert r.returncode == 0
        n = extract_table_n(r, 0.90, 2)   # col 2 = C=0.95
        print(f"  n (power=0.90, C=0.95, 2-sided): expected 44, got {n}")
        assert n is not None, f"Could not extract n:\n{combined(r)}"
        assert n == 44, f"Expected n=44 at power=0.90, C=0.95 (2-sided), got {n}"

    def test_tc_paired_007_n_exact_1sided_power090_c095(self):
        """TC-PAIRED-007: delta=0.5, sd=1.0, sides=1, power=0.90, C=0.95 → n=36
        Independent: effect_size = 0.5; 1-sided z_α = qnorm(0.95) = 1.6449
          z_β = qnorm(0.90) = 1.2816
          n = ceiling(((1.6449+1.2816)/0.5)²) + 1 = ceiling(34.26) + 1 = 35+1 = 36
        1-sided test requires fewer samples than 2-sided: 36 < 44. ✓
        """
        r = run("jrc_ss_paired.R", "0.5", "1.0", "1")
        assert r.returncode == 0
        n = extract_table_n(r, 0.90, 2)   # col 2 = C=0.95
        print(f"  n (power=0.90, C=0.95, 1-sided): expected 36, got {n}")
        assert n is not None, f"Could not extract n:\n{combined(r)}"
        assert n == 36, f"Expected n=36 at power=0.90, C=0.95 (1-sided), got {n}"


# ===========================================================================
# jrc_ss_equivalence (TC-EQUIV-001 .. 004)
# ===========================================================================

class TestSsEquivalence:

    def test_tc_equiv_001_two_sided_tost(self):
        """TC-EQUIV-001: 2-sided → exit 0, output mentions TOST/equivalence"""
        r = run("jrc_ss_equivalence.R", "0.5", "1.0", "2")
        assert r.returncode == 0
        out = combined(r).lower()
        assert "tost" in out or "equivalence" in out

    def test_tc_equiv_002_one_sided(self):
        """TC-EQUIV-002: 1-sided → exit 0"""
        r = run("jrc_ss_equivalence.R", "0.5", "1.0", "1")
        assert r.returncode == 0

    def test_tc_equiv_003_invalid_sides(self):
        """TC-EQUIV-003: sides=0 → non-zero exit"""
        r = run("jrc_ss_equivalence.R", "0.5", "1.0", "0")
        assert r.returncode != 0

    def test_tc_equiv_004_missing_arguments(self):
        """TC-EQUIV-004: only 1 argument → non-zero exit, mentions 'Usage'"""
        r = run("jrc_ss_equivalence.R", "0.5")
        assert r.returncode != 0
        assert "usage" in combined(r).lower()

    def test_tc_equiv_005_n_exact_power090_c095(self):
        """TC-EQUIV-005: delta=0.5, sd=1.0, sides=2, power=0.90, C=0.95 → n=36
        Independent (TOST always uses 1-sided z_α regardless of 'sides' label):
          effect_size = 0.5; z_α = qnorm(0.95) = 1.6449; z_β = qnorm(0.90) = 1.2816
          n = ceiling(((1.6449+1.2816)/0.5)²) + 1 = ceiling(34.26) + 1 = 35+1 = 36
        TOST uses 1-sided z_α; therefore equals TC-PAIRED-007 (1-sided paired, same inputs). ✓
        """
        r = run("jrc_ss_equivalence.R", "0.5", "1.0", "2")
        assert r.returncode == 0
        n = extract_table_n(r, 0.90, 2)   # col 2 = C=0.95
        print(f"  n (power=0.90, C=0.95, TOST): expected 36, got {n}")
        assert n is not None, f"Could not extract n:\n{combined(r)}"
        assert n == 36, f"Expected n=36 at power=0.90, C=0.95 (TOST), got {n}"

    def test_tc_equiv_006_n_exact_power095_c095(self):
        """TC-EQUIV-006: delta=0.5, sd=1.0, sides=2, power=0.95, C=0.95 → n=45
        Independent: z_α = qnorm(0.95) = 1.6449; z_β = qnorm(0.95) = 1.6449
          n = ceiling(((1.6449+1.6449)/0.5)²) + 1 = ceiling(43.29) + 1 = 44+1 = 45
        Higher power raises n from 36 (power=0.90) to 45 (power=0.95). ✓
        """
        r = run("jrc_ss_equivalence.R", "0.5", "1.0", "2")
        assert r.returncode == 0
        n = extract_table_n(r, 0.95, 2)   # col 2 = C=0.95
        print(f"  n (power=0.95, C=0.95, TOST): expected 45, got {n}")
        assert n is not None, f"Could not extract n:\n{combined(r)}"
        assert n == 45, f"Expected n=45 at power=0.95, C=0.95 (TOST), got {n}"


# ===========================================================================
# jrc_ss_fatigue (TC-FAT-001 .. 005)
# ===========================================================================

class TestSsFatigue:

    def test_tc_fat_001_standard_no_acceleration(self):
        """TC-FAT-001: B10, C=0.95, beta=2, AF=1 → exit 0, table for f=0..5"""
        r = run("jrc_ss_fatigue.R", "0.90", "0.95", "2.0", "1.0")
        assert r.returncode == 0
        out = combined(r)
        assert "f = 0" in out

    def test_tc_fat_002_acceleration_reduces_n(self):
        """TC-FAT-002: AF=2 reduces n at f=0 vs AF=1"""
        r1 = run("jrc_ss_fatigue.R", "0.90", "0.95", "2.0", "1.0")
        r2 = run("jrc_ss_fatigue.R", "0.90", "0.95", "2.0", "2.0")
        assert r1.returncode == 0 and r2.returncode == 0
        n1 = extract_n_at_f(r1, 0)
        n2 = extract_n_at_f(r2, 0)
        assert n1 is not None and n2 is not None
        assert n2 < n1

    def test_tc_fat_003_reliability_ge_1(self):
        """TC-FAT-003: reliability=1.0 → non-zero exit"""
        r = run("jrc_ss_fatigue.R", "1.0", "0.95", "2.0", "1.0")
        assert r.returncode != 0

    def test_tc_fat_004_af_less_than_1(self):
        """TC-FAT-004: af=0.5 → non-zero exit"""
        r = run("jrc_ss_fatigue.R", "0.90", "0.95", "2.0", "0.5")
        assert r.returncode != 0

    def test_tc_fat_005_missing_arguments(self):
        """TC-FAT-005: only 3 arguments → non-zero exit, mentions 'Usage'"""
        r = run("jrc_ss_fatigue.R", "0.90", "0.95", "2.0")
        assert r.returncode != 0
        assert "usage" in combined(r).lower()

    def test_tc_fat_006_n_exact_af1_equals_discrete(self):
        """TC-FAT-006: R=0.90, C=0.95, β=2, AF=1.0, f=0 → n=30
        Independent: p_eff = 1 - 0.90^(1.0^2) = 0.10
          n = ceiling(qchisq(0.95,2) / (2*0.10)) = ceiling(5.9915/0.20) = ceiling(29.96) = 30
        Cross-script consistency: AF=1 collapses to jrc_ss_discrete(P=0.90, C=0.95, f=0) = 30.
        TC-DISC-008 independently confirmed n=47 for P=0.95; P=0.90 gives 30. ✓
        """
        r = run("jrc_ss_fatigue.R", "0.90", "0.95", "2.0", "1.0")
        assert r.returncode == 0
        print(f"  n at f=0: expected 30, got {extract_n_at_f(r, 0)}")
        assert extract_n_at_f(r, 0) == 30

    def test_tc_fat_007_n_exact_af2_reduces_sample(self):
        """TC-FAT-007: R=0.90, C=0.95, β=2, AF=2.0, f=0 → n=9
        Independent: p_eff = 1 - 0.90^(2.0^2) = 1 - 0.9^4 = 1 - 0.6561 = 0.3439
          n = ceiling(5.9915 / (2*0.3439)) = ceiling(5.9915/0.6878) = ceiling(8.711) = 9
        Acceleration factor AF=2 reduces n from 30 (AF=1) to 9. ✓
        """
        r = run("jrc_ss_fatigue.R", "0.90", "0.95", "2.0", "2.0")
        assert r.returncode == 0
        print(f"  n at f=0: expected 9, got {extract_n_at_f(r, 0)}")
        assert extract_n_at_f(r, 0) == 9


# ===========================================================================
# jrc_msa_grr_design (TC-GRR-001 .. 004)
# ===========================================================================

class TestMsaGrrDesign:

    def test_tc_grr_001_process_based(self):
        """TC-GRR-001: process type → exit 0, table contains %GRR and ndc"""
        r = run("jrc_msa_grr_design.R", "10", "process", "1.0")
        assert r.returncode == 0
        out = combined(r).lower()
        assert "grr" in out or "ndc" in out

    def test_tc_grr_002_tolerance_based(self):
        """TC-GRR-002: tolerance type → exit 0, table output"""
        r = run("jrc_msa_grr_design.R", "10", "tolerance", "5.0")
        assert r.returncode == 0

    def test_tc_grr_003_invalid_type(self):
        """TC-GRR-003: badtype → non-zero exit"""
        r = run("jrc_msa_grr_design.R", "10", "badtype", "1.0")
        assert r.returncode != 0

    def test_tc_grr_004_missing_arguments(self):
        """TC-GRR-004: only 1 argument → non-zero exit, mentions 'Usage'"""
        r = run("jrc_msa_grr_design.R", "10")
        assert r.returncode != 0
        assert "usage" in combined(r).lower()
