"""
OQ test suite — Clinical module: jrc_clinical_ancova

Maps to JR-VP-CLIN-001 (Rev 5).

  TC-CLIN-ANCOVA-001  Valid inputs -> exit 0, header, group count
  TC-CLIN-ANCOVA-002  PUBLISHED ANCHOR — anorexia (MASS): Type III group test
                      F 7.8680, p 0.0008
  TC-CLIN-ANCOVA-003  Type III covariate (prewt) test F 7.2660, p 0.00885
  TC-CLIN-ANCOVA-004  Adjusted (LS) means CBT 85.5743 / Cont 81.4773 / FT 90.1374
  TC-CLIN-ANCOVA-005  Tukey-adjusted pairwise contrast Cont - FT
  TC-CLIN-ANCOVA-006  Covariate coefficient prewt +0.4345
  TC-CLIN-ANCOVA-007  --conf 0.90 -> tighter adjusted-mean CI
  TC-CLIN-ANCOVA-008  Missing required column -> non-zero exit
  TC-CLIN-ANCOVA-009  --covariates omitted -> non-zero exit
  TC-CLIN-ANCOVA-010  Missing covariate column -> non-zero exit
  TC-CLIN-ANCOVA-011  Duplicate id -> non-zero exit
  TC-CLIN-ANCOVA-012  Fewer than two groups -> non-zero exit
  TC-CLIN-ANCOVA-013  Direct Rscript without RENV_PATHS_ROOT -> non-zero

The load-bearing cases are TC-002/004: the analysis is anchored to the
anorexia dataset (Hand et al. / Venables & Ripley, MASS), the canonical ANCOVA
teaching example: Postwt ~ Prewt + Treat. The adjusted (least-squares) means
and Type III joint tests are produced by the validated `emmeans` package
(joint_tests, emmeans), on top of a base-R lm. The published adjusted means are
85.6 / 81.5 / 90.1 and the group effect is significant after adjustment
(F = 7.87, p = 0.0008); this suite anchors to those documented values.
"""
import re
import sys

if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from conftest import run, combined, data, report_int, run_direct_rscript

SCRIPT = "jrc_clinical_ancova.R"
FIX    = "ancova_anorexia.csv"


class TestClinicalAncova:

    def test_tc_clin_ancova_001_happy_path(self):
        r = run(SCRIPT, data(FIX), "--covariates", "prewt")
        assert r.returncode == 0, combined(r)
        out = combined(r)
        assert "ANCOVA — outcome by group, adjusted for covariates" in out
        assert report_int(r, "Subjects") == 72

    def test_tc_clin_ancova_002_type3_group_test(self):
        r = run(SCRIPT, data(FIX), "--covariates", "prewt")
        assert re.search(r"group\s+F =\s+7.8680\s+df = 2, 68\s+p = 0.0008438",
                         combined(r))

    def test_tc_clin_ancova_003_type3_covariate_test(self):
        r = run(SCRIPT, data(FIX), "--covariates", "prewt")
        assert re.search(r"prewt\s+F =\s+7.2660\s+df = 1, 68\s+p = 0.00885",
                         combined(r))

    def test_tc_clin_ancova_004_adjusted_means(self):
        r = run(SCRIPT, data(FIX), "--covariates", "prewt")
        out = combined(r)
        assert re.search(r"CBT\s+adj. mean =\s+85.5743", out)
        assert re.search(r"Cont\s+adj. mean =\s+81.4773", out)
        assert re.search(r"FT\s+adj. mean =\s+90.1374", out)

    def test_tc_clin_ancova_005_pairwise_contrast(self):
        r = run(SCRIPT, data(FIX), "--covariates", "prewt")
        # Cont - FT is the significant Tukey-adjusted contrast.
        assert re.search(r"Cont - FT\s+diff =\s+-8.6601.*p = 0.0005484", combined(r))

    def test_tc_clin_ancova_006_covariate_coef(self):
        r = run(SCRIPT, data(FIX), "--covariates", "prewt")
        assert re.search(r"prewt\s+coef =\s+\+0.4345\s+\(SE 0.1612\)", combined(r))

    def test_tc_clin_ancova_007_lower_conf_tightens_ci(self):
        r = run(SCRIPT, data(FIX), "--covariates", "prewt", "--conf", "0.90")
        assert "90% CI 83.4121, 87.7365" in combined(r)   # CBT, tighter than 95%

    def test_tc_clin_ancova_008_missing_column(self):
        r = run(SCRIPT, data("means_sleep_student1908.csv"), "--covariates", "prewt")
        assert r.returncode != 0
        assert "Missing column(s)" in combined(r)

    def test_tc_clin_ancova_009_covariates_required(self):
        r = run(SCRIPT, data(FIX))
        assert r.returncode != 0
        assert "--covariates is required" in combined(r)

    def test_tc_clin_ancova_010_missing_covariate(self):
        r = run(SCRIPT, data(FIX), "--covariates", "nosuchcol")
        assert r.returncode != 0
        assert "Missing column(s)" in combined(r)

    def test_tc_clin_ancova_011_duplicate_id(self):
        r = run(SCRIPT, data("ancova_dup_id.csv"), "--covariates", "prewt")
        assert r.returncode != 0
        assert "Duplicate id(s) found" in combined(r)

    def test_tc_clin_ancova_012_one_group(self):
        r = run(SCRIPT, data("ancova_one_group.csv"), "--covariates", "prewt")
        assert r.returncode != 0
        assert "at least two levels" in combined(r)

    def test_tc_clin_ancova_013_direct_rscript_blocked(self):
        r = run_direct_rscript("repos/clinical/R/jrc_clinical_ancova.R",
                               data(FIX), "--covariates", "prewt")
        assert r.returncode != 0
        assert "RENV_PATHS_ROOT" in combined(r)
