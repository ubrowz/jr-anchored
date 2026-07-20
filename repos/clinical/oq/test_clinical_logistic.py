"""
OQ test suite — Clinical module: jrc_clinical_logistic

Maps to JR-VP-CLIN-001 (Rev 5).

  TC-CLIN-LOGIT-001  Valid inputs -> exit 0, header, subject/event counts
  TC-CLIN-LOGIT-002  PUBLISHED ANCHOR — birthwt (Hosmer & Lemeshow): smoke OR
                     1.9557 (95% CI 1.0326, 3.7042)
  TC-CLIN-LOGIT-003  lwt OR 0.9879 (95% CI 0.9761, 0.9999)
  TC-CLIN-LOGIT-004  age OR 0.9618, p 0.2334
  TC-CLIN-LOGIT-005  Global likelihood-ratio test chisq 11.7926, df 3, p 0.0081
  TC-CLIN-LOGIT-006  Model fit AIC 230.88
  TC-CLIN-LOGIT-007  Model AUC 0.6531 (dx_roc kernel)
  TC-CLIN-LOGIT-008  --conf 0.90 -> tighter smoke OR CI
  TC-CLIN-LOGIT-009  Missing required column -> non-zero exit
  TC-CLIN-LOGIT-010  --predictors omitted -> non-zero exit
  TC-CLIN-LOGIT-011  Non-binary outcome (3 levels) -> non-zero exit
  TC-CLIN-LOGIT-012  Duplicate id -> non-zero exit
  TC-CLIN-LOGIT-013  Direct Rscript without RENV_PATHS_ROOT -> non-zero

The load-bearing case is TC-002/003: the fit is anchored to the low-birth-
weight data of Hosmer & Lemeshow (the canonical logistic-regression teaching
dataset, shipped in MASS as `birthwt`), model low ~ age + lwt + smoke. Smoking
roughly doubles the odds of low birth weight (OR 1.96), and mother's weight is
protective (OR 0.99 per lb) — both documented results. The estimates come from
base R glm(family = binomial); the model AUC reuses the tie-aware Mann-Whitney
kernel validated for jrc_clinical_dx_roc.
"""
import re
import sys

if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from conftest import run, combined, data, report_int, run_direct_rscript

SCRIPT = "jrc_clinical_logistic.R"
FIX    = "logistic_birthwt.csv"
COV    = ("--predictors", "age,lwt,smoke")


def _or_row(out, term):
    m = re.search(rf"^{re.escape(term)}\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+(-?[\d.]+)\s+([\d.eE+-]+)",
                  out, re.M)
    return tuple(float(x) for x in m.groups()) if m else None


class TestClinicalLogistic:

    def test_tc_clin_logit_001_happy_path(self):
        r = run(SCRIPT, data(FIX), *COV)
        assert r.returncode == 0, combined(r)
        out = combined(r)
        assert "Logistic regression for a binary outcome" in out
        assert report_int(r, "Subjects") == 189

    def test_tc_clin_logit_002_smoke_or_anchor(self):
        r = run(SCRIPT, data(FIX), *COV)
        row = _or_row(combined(r), "smokesmoker")
        assert row is not None, combined(r)
        assert row[0] == 1.9557 and (row[1], row[2]) == (1.0326, 3.7042)

    def test_tc_clin_logit_003_lwt_or(self):
        r = run(SCRIPT, data(FIX), *COV)
        row = _or_row(combined(r), "lwt")
        assert row[0] == 0.9879 and (row[1], row[2]) == (0.9761, 0.9999)

    def test_tc_clin_logit_004_age_or(self):
        r = run(SCRIPT, data(FIX), *COV)
        row = _or_row(combined(r), "age")
        assert row[0] == 0.9618
        assert abs(row[4] - 0.2334) < 1e-4

    def test_tc_clin_logit_005_lr_test(self):
        r = run(SCRIPT, data(FIX), *COV)
        assert re.search(r"chisq = 11.7926\s+df = 3\s+p = 0.008128", combined(r))

    def test_tc_clin_logit_006_aic(self):
        r = run(SCRIPT, data(FIX), *COV)
        assert re.search(r"AIC\s+:\s*230.88", combined(r))

    def test_tc_clin_logit_007_model_auc(self):
        r = run(SCRIPT, data(FIX), *COV)
        assert re.search(r"Model AUC \(in-sample\)\s+:\s*0.6531", combined(r))

    def test_tc_clin_logit_008_lower_conf_tightens_ci(self):
        r = run(SCRIPT, data(FIX), *COV, "--conf", "0.90")
        row = _or_row(combined(r), "smokesmoker")
        assert row[0] == 1.9557
        assert (row[1], row[2]) == (1.1442, 3.3427)   # tighter than 95%

    def test_tc_clin_logit_009_missing_column(self):
        r = run(SCRIPT, data("means_sleep_student1908.csv"), "--predictors", "value")
        assert r.returncode != 0
        assert "Missing column(s)" in combined(r)

    def test_tc_clin_logit_010_predictors_required(self):
        r = run(SCRIPT, data(FIX))
        assert r.returncode != 0
        assert "--predictors is required" in combined(r)

    def test_tc_clin_logit_011_nonbinary_outcome(self):
        r = run(SCRIPT, data("log_three_outcomes.csv"), "--predictors", "age")
        assert r.returncode != 0
        assert "exactly two levels" in combined(r)

    def test_tc_clin_logit_012_duplicate_id(self):
        r = run(SCRIPT, data("log_dup_id.csv"), "--predictors", "age")
        assert r.returncode != 0
        assert "Duplicate id(s) found" in combined(r)

    def test_tc_clin_logit_013_direct_rscript_blocked(self):
        r = run_direct_rscript("repos/clinical/R/jrc_clinical_logistic.R",
                               data(FIX), *COV)
        assert r.returncode != 0
        assert "RENV_PATHS_ROOT" in combined(r)
