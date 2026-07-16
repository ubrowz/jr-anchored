"""
OQ test suite — Clinical module: jrc_clinical_dx_accuracy

Maps to validation plan JR-VP-CLIN-001 (Rev 2) as follows:

  TC-CLIN-DXACC-001  Valid inputs -> exit 0, report header present
  TC-CLIN-DXACC-002  2x2 counts from the fixture -> TP 79, FP 6, FN 16, TN 99
  TC-CLIN-DXACC-003  Sensitivity + Clopper-Pearson exact CI
  TC-CLIN-DXACC-004  Specificity + Clopper-Pearson exact CI
  TC-CLIN-DXACC-005  Overall accuracy + exact CI
  TC-CLIN-DXACC-006  LR+ and its log (Simel) interval
  TC-CLIN-DXACC-007  LR- and its log (Simel) interval
  TC-CLIN-DXACC-008  PPV/NPV at the study prevalence, + the validity caveat
  TC-CLIN-DXACC-009  --ci wilson -> Wilson interval, strictly inside exact
  TC-CLIN-DXACC-010  --prevalence 0.02 -> Bayes-adjusted PPV/NPV
  TC-CLIN-DXACC-011  --conf 0.90 -> interval strictly narrower than 0.95
  TC-CLIN-DXACC-012  --positive override resolves non-standard labels
  TC-CLIN-DXACC-013  Rows with missing values dropped and reported
  TC-CLIN-DXACC-014  --ci bogus -> non-zero exit
  TC-CLIN-DXACC-015  --prevalence out of range -> non-zero exit
  TC-CLIN-DXACC-016  Missing required column -> non-zero exit
  TC-CLIN-DXACC-017  Duplicate id -> non-zero exit
  TC-CLIN-DXACC-018  Unrecognised labels -> non-zero exit
  TC-CLIN-DXACC-019  No reference-negative subjects -> non-zero exit
  TC-CLIN-DXACC-020  Direct Rscript call without RENV_PATHS_ROOT -> non-zero

Numeric references. The fixture dx_accuracy_n200_seed42.csv is a fixed 2x2:
TP 79, FP 6, FN 16, TN 99 (n1 = 95 reference-positive, n0 = 105 reference-
negative, N = 200). All expected values below were computed independently of
the script, from the closed-form definitions, and confirmed against it:

  sens = 79/95  = 0.831578...   spec = 99/105 = 0.942857...
  acc  = 178/200 = 0.89         PPV  = 79/85  = 0.929411...
                                NPV  = 99/115 = 0.860869...
  LR+  = sens/(1-spec) = 0.8315789/0.0571429 = 14.5526...
  LR-  = (1-sens)/spec = 0.1684211/0.9428571 =  0.178642...

  Clopper-Pearson exact 95% CI for 79/95 -> (0.7410, 0.9006)  [R binom.test]

  Wilson 95% score CI for 79/95, z = 1.959964:
    den = 1 + z^2/95 = 1.040437
    ctr = (0.8315789 + z^2/190)/den = 0.851797/1.040437 = 0.818694
    hw  = z*sqrt(0.8315789*0.1684211/95 + z^2/(4*95^2))/den = 0.074891
    -> (0.743803, 0.893585) = (0.7438, 0.8936). Narrower than exact, as
       Wilson must be.

  LR+ log (Simel 1991) 95% CI:
    SE(log LR+) = sqrt((1-sens)/(sens*n1) + spec/((1-spec)*n0))
                = sqrt(0.1684211/79 + 0.9428571/6) = sqrt(0.15927477)
                = 0.399093
    exp(log(14.5526) +/- 1.959964*0.399093) = (6.6563, 31.8163)

  Bayes-adjusted PPV at prevalence 0.02:
    PPV = sens*p / (sens*p + (1-spec)*(1-p))
        = 0.8315789*0.02 / (0.8315789*0.02 + 0.0571429*0.98)
        = 0.01663158 / 0.07263158 = 0.228986... = 0.2290
    Its interval propagates the sens/spec bounds of whichever --ci method is
    in force, at full internal precision, giving (0.1117, 0.4637) under the
    default exact interval.
    This is the FDA (2007) caution made concrete: the same test reads
    PPV 0.9294 at the study's 47.5% prevalence and 0.2290 at 2%.
"""
import re
import sys

# Force UTF-8 stdout/stderr on Windows (cp1252 cannot encode emoji)
if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if sys.stderr.encoding and sys.stderr.encoding.lower() != "utf-8":
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

from conftest import (run, combined, data, report_est_ci, report_int,
                      run_direct_rscript)

SCRIPT = "jrc_clinical_dx_accuracy.R"
FIX    = "dx_accuracy_n200_seed42.csv"


class TestClinicalDxAccuracy:

    def test_tc_clin_dxacc_001_happy_path_exits_zero(self):
        r = run(SCRIPT, data(FIX))
        assert r.returncode == 0
        out = combined(r)
        assert "Diagnostic accuracy" in out
        assert "reference standard" in out

    def test_tc_clin_dxacc_002_two_by_two_counts(self):
        r = run(SCRIPT, data(FIX))
        out = combined(r)
        assert r.returncode == 0
        # TP 79, FP 6 | FN 16, TN 99 | margins 95 ref+, 105 ref-, N 200
        assert re.search(r"test \+\s+79\s+6\s+85", out)
        assert re.search(r"test -\s+16\s+99\s+115", out)
        assert re.search(r"total\s+95\s+105\s+200", out)
        assert report_int(r, "Subjects") == 200

    def test_tc_clin_dxacc_003_sensitivity_exact_ci(self):
        r = run(SCRIPT, data(FIX))
        est, lo, hi = report_est_ci(r, "Sensitivity")
        assert est == 0.8316          # 79/95 = 0.831578...
        assert (lo, hi) == (0.7410, 0.9006)

    def test_tc_clin_dxacc_004_specificity_exact_ci(self):
        r = run(SCRIPT, data(FIX))
        est, lo, hi = report_est_ci(r, "Specificity")
        assert est == 0.9429          # 99/105 = 0.942857...
        assert (lo, hi) == (0.8798, 0.9787)

    def test_tc_clin_dxacc_005_accuracy_exact_ci(self):
        r = run(SCRIPT, data(FIX))
        est, lo, hi = report_est_ci(r, "Accuracy")
        assert est == 0.8900          # 178/200
        assert (lo, hi) == (0.8382, 0.9298)

    def test_tc_clin_dxacc_006_lr_positive_simel_ci(self):
        r = run(SCRIPT, data(FIX))
        est, lo, hi = report_est_ci(r, "LR+")
        assert est == 14.5526
        assert (lo, hi) == (6.6563, 31.8163)

    def test_tc_clin_dxacc_007_lr_negative_simel_ci(self):
        r = run(SCRIPT, data(FIX))
        est, lo, hi = report_est_ci(r, "LR-")
        assert est == 0.1786
        assert (lo, hi) == (0.1140, 0.2799)

    def test_tc_clin_dxacc_008_ppv_npv_study_prevalence_with_caveat(self):
        r = run(SCRIPT, data(FIX))
        out = combined(r)
        ppv = report_est_ci(r, "PPV")
        npv = report_est_ci(r, "NPV")
        assert ppv[0] == 0.9294       # 79/85
        assert npv[0] == 0.8609       # 99/115
        assert "study prevalence (0.4750)" in out
        # The validity caveat must be present when no --prevalence is given.
        assert "valid ONLY if" in out

    def test_tc_clin_dxacc_009_wilson_ci_is_inside_exact(self):
        exact  = report_est_ci(run(SCRIPT, data(FIX)), "Sensitivity")
        wilson = report_est_ci(run(SCRIPT, data(FIX), "--ci", "wilson"),
                               "Sensitivity")
        assert wilson[0] == exact[0] == 0.8316     # same point estimate
        assert (wilson[1], wilson[2]) == (0.7438, 0.8936)
        # Wilson is the shorter interval and sits strictly inside exact.
        assert wilson[1] > exact[1] and wilson[2] < exact[2]

    def test_tc_clin_dxacc_010_bayes_adjusted_ppv_npv(self):
        r = run(SCRIPT, data(FIX), "--prevalence", "0.02")
        out = combined(r)
        assert r.returncode == 0
        assert "Bayes-adjusted to prevalence 0.0200" in out
        ppv_adj = report_est_ci(r, "PPV (adj)")
        npv_adj = report_est_ci(r, "NPV (adj)")
        assert ppv_adj[0] == 0.2290
        # Bounds propagate the EXACT (Clopper-Pearson) sens/spec interval,
        # this script's default. They are correspondingly wider than the
        # Wilson-propagated bounds obtained under --ci wilson.
        assert (ppv_adj[1], ppv_adj[2]) == (0.1117, 0.4637)
        assert npv_adj[0] == 0.9964
        # The unadjusted PPV must still be shown, and be far higher.
        assert report_est_ci(r, "PPV ")[0] == 0.9294

    def test_tc_clin_dxacc_011_lower_conf_narrows_interval(self):
        c95 = report_est_ci(run(SCRIPT, data(FIX)), "Sensitivity")
        c90 = report_est_ci(run(SCRIPT, data(FIX), "--conf", "0.90"),
                            "Sensitivity")
        assert c90[0] == c95[0]
        assert c90[1] > c95[1] and c90[2] < c95[2]

    def test_tc_clin_dxacc_012_positive_override_for_custom_labels(self):
        r = run(SCRIPT, data("dx_custom_labels.csv"), "--positive", "detected")
        assert r.returncode == 0
        assert report_est_ci(r, "Sensitivity")[0] == 0.8000   # 4/5
        assert report_est_ci(r, "Specificity")[0] == 0.8000   # 4/5

    def test_tc_clin_dxacc_013_missing_rows_dropped_and_reported(self):
        r = run(SCRIPT, data("dx_missing_rows.csv"))
        assert r.returncode == 0
        assert "4 evaluable" in combined(r)
        assert "2 row(s) dropped" in combined(r)

    def test_tc_clin_dxacc_014_bad_ci_method_rejected(self):
        r = run(SCRIPT, data(FIX), "--ci", "bogus")
        assert r.returncode != 0
        assert "--ci must be" in combined(r)

    def test_tc_clin_dxacc_015_prevalence_out_of_range_rejected(self):
        r = run(SCRIPT, data(FIX), "--prevalence", "1.5")
        assert r.returncode != 0
        assert "--prevalence" in combined(r)

    def test_tc_clin_dxacc_016_missing_column_rejected(self):
        # dx_roc fixture has a 'score' column, not 'result'.
        r = run(SCRIPT, data("dx_roc_n200_seed7.csv"))
        assert r.returncode != 0
        assert "Missing column(s): result" in combined(r)

    def test_tc_clin_dxacc_017_duplicate_id_rejected(self):
        r = run(SCRIPT, data("dx_dup_id.csv"))
        assert r.returncode != 0
        assert "Duplicate id(s) found" in combined(r)

    def test_tc_clin_dxacc_018_unrecognised_labels_rejected(self):
        r = run(SCRIPT, data("dx_bad_labels.csv"))
        assert r.returncode != 0
        assert "does not recognise" in combined(r)

    def test_tc_clin_dxacc_019_no_reference_negative_rejected(self):
        r = run(SCRIPT, data("dx_all_reference_positive.csv"))
        assert r.returncode != 0
        assert "specificity is undefined" in combined(r)

    def test_tc_clin_dxacc_020_direct_rscript_blocked_without_renv(self):
        r = run_direct_rscript("repos/clinical/R/jrc_clinical_dx_accuracy.R",
                               data(FIX))
        assert r.returncode != 0
        assert "RENV_PATHS_ROOT" in combined(r)
