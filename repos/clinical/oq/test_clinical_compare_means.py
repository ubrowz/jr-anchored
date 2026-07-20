"""
OQ test suite — Clinical module: jrc_clinical_compare_means

Maps to JR-VP-CLIN-001 (Rev 5).

  TC-CLIN-CMEAN-001  Valid inputs -> exit 0, header, group/subject counts
  TC-CLIN-CMEAN-002  PUBLISHED ANCHOR — Student (1908) sleep data, Welch t-test
  TC-CLIN-CMEAN-003  Mean difference and CI (Welch)
  TC-CLIN-CMEAN-004  Cohen's d and Hedges' g on the sleep data
  TC-CLIN-CMEAN-005  Mann-Whitney / Wilcoxon rank-sum result
  TC-CLIN-CMEAN-006  --test student -> equal-variance t (df = 18)
  TC-CLIN-CMEAN-007  --conf 0.90 -> tighter mean-difference CI
  TC-CLIN-CMEAN-008  Per-group Shapiro-Wilk normality note
  TC-CLIN-CMEAN-009  PUBLISHED ANCHOR — PlantGrowth one-way ANOVA (3 groups)
  TC-CLIN-CMEAN-010  Missing required column -> non-zero exit
  TC-CLIN-CMEAN-011  Duplicate id -> non-zero exit
  TC-CLIN-CMEAN-012  Fewer than two groups -> non-zero exit
  TC-CLIN-CMEAN-013  A group with < 2 observations -> non-zero exit
  TC-CLIN-CMEAN-014  Bad --test value -> non-zero exit
  TC-CLIN-CMEAN-015  Direct Rscript without RENV_PATHS_ROOT -> non-zero

The load-bearing case is TC-002/003: the two-group comparison is anchored to
Student's (1908) original extra-sleep data (the dataset the t-test was invented
on, shipped with R). The Welch two-sample t-test on these data gives
t = -1.8608, df = 17.78, p = 0.0794 with a mean difference of -1.58; the
one-way ANOVA anchor uses the PlantGrowth data (F = 4.8461, p = 0.0159). The
test statistics are computed by base R (t.test, wilcox.test, anova) — this
suite confirms the script invokes them correctly and reports faithfully
against these documented values.
"""
import re
import sys

if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from conftest import run, combined, data, report_int, run_direct_rscript

SCRIPT = "jrc_clinical_compare_means.R"
SLEEP  = "means_sleep_student1908.csv"
PLANT  = "means_plantgrowth.csv"


class TestClinicalCompareMeans:

    def test_tc_clin_cmean_001_happy_path(self):
        r = run(SCRIPT, data(SLEEP))
        assert r.returncode == 0, combined(r)
        out = combined(r)
        assert "Comparison of a continuous outcome between groups" in out
        assert report_int(r, "Subjects") == 20

    def test_tc_clin_cmean_002_welch_anchor(self):
        r = run(SCRIPT, data(SLEEP))
        assert re.search(r"t = -1.8608\s+df = 17.7765\s+p = 0.07939", combined(r))

    def test_tc_clin_cmean_003_mean_difference_ci(self):
        r = run(SCRIPT, data(SLEEP))
        assert "-1.5800  (95% CI -3.3655, +0.2055)" in combined(r)

    def test_tc_clin_cmean_004_effect_size(self):
        r = run(SCRIPT, data(SLEEP))
        assert re.search(r"Cohen's d\s*:\s*-0.8322\s+Hedges' g\s*:\s*-0.7970",
                         combined(r))

    def test_tc_clin_cmean_005_mann_whitney(self):
        r = run(SCRIPT, data(SLEEP))
        assert re.search(r"W = 25.5\s+p = 0.06582", combined(r))

    def test_tc_clin_cmean_006_student_option(self):
        r = run(SCRIPT, data(SLEEP), "--test", "student")
        out = combined(r)
        assert "Student's t-test (equal variance)" in out
        assert re.search(r"t = -1.8608\s+df = 18.0000\s+p = 0.07919", out)

    def test_tc_clin_cmean_007_lower_conf_tightens_ci(self):
        r = run(SCRIPT, data(SLEEP), "--conf", "0.90")
        assert "90% CI -3.0534, -0.1066" in combined(r)

    def test_tc_clin_cmean_008_normality_note(self):
        r = run(SCRIPT, data(SLEEP))
        assert "Shapiro p =" in combined(r)

    def test_tc_clin_cmean_009_anova_anchor(self):
        r = run(SCRIPT, data(PLANT))
        out = combined(r)
        assert "One-way ANOVA (3 groups)" in out
        assert re.search(r"F = 4.8461\s+df = 2, 27\s+p = 0.01591", out)

    def test_tc_clin_cmean_010_missing_column(self):
        r = run(SCRIPT, data("km_aml_miller1981.csv"))  # no 'value'/'group'
        assert r.returncode != 0
        assert "Missing column(s)" in combined(r)

    def test_tc_clin_cmean_011_duplicate_id(self):
        r = run(SCRIPT, data("cmp_dup_id.csv"))
        assert r.returncode != 0
        assert "Duplicate id(s) found" in combined(r)

    def test_tc_clin_cmean_012_one_group(self):
        r = run(SCRIPT, data("cmp_one_group.csv"))
        assert r.returncode != 0
        assert "At least two groups" in combined(r)

    def test_tc_clin_cmean_013_group_too_small(self):
        r = run(SCRIPT, data("cmp_one_per_group.csv"))
        assert r.returncode != 0
        assert "fewer than 2 observations" in combined(r)

    def test_tc_clin_cmean_014_bad_test(self):
        r = run(SCRIPT, data(SLEEP), "--test", "bogus")
        assert r.returncode != 0
        assert "--test must be" in combined(r)

    def test_tc_clin_cmean_015_direct_rscript_blocked(self):
        r = run_direct_rscript("repos/clinical/R/jrc_clinical_compare_means.R",
                               data(SLEEP))
        assert r.returncode != 0
        assert "RENV_PATHS_ROOT" in combined(r)
