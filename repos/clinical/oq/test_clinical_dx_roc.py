"""
OQ test suite — Clinical module: jrc_clinical_dx_roc

Maps to validation plan JR-VP-CLIN-001 (Rev 2) as follows:

  TC-CLIN-DXROC-001  Valid inputs -> exit 0, report header present
  TC-CLIN-DXROC-002  PNG written to ~/Downloads/
  TC-CLIN-DXROC-003  PUBLISHED ANCHOR — Hanley & McNeil (1982) Table 1 data
                     -> AUC 0.8932, matching the published 0.893
  TC-CLIN-DXROC-004  Continuous fixture: AUC, DeLong SE and CI
  TC-CLIN-DXROC-005  Tie-heavy fixture: AUC with the 0.5 tie kernel
  TC-CLIN-DXROC-006  Youden cutoff, J, sensitivity and specificity
  TC-CLIN-DXROC-007  Cutoff reported as an OBSERVED value with an explicit rule
  TC-CLIN-DXROC-008  H0: AUC = 0.5 reported with z and p
  TC-CLIN-DXROC-009  --direction lower reflects AUC to 1 - AUC
  TC-CLIN-DXROC-010  --direction lower on this data -> degenerate cutoff
                     reported as none, plus the AUC < 0.5 warning
  TC-CLIN-DXROC-011  --ci-method logit stays inside (0, 1) and differs
  TC-CLIN-DXROC-012  --conf 0.90 -> interval strictly narrower than 0.95
  TC-CLIN-DXROC-013  --direction bogus -> non-zero exit
  TC-CLIN-DXROC-014  Missing required column -> non-zero exit
  TC-CLIN-DXROC-015  Duplicate id -> non-zero exit
  TC-CLIN-DXROC-016  No reference-negative subjects -> non-zero exit
  TC-CLIN-DXROC-017  Direct Rscript call without RENV_PATHS_ROOT -> non-zero

Numeric references.

TC-003 is the load-bearing one. The AUC and its DeLong variance are
implemented in base R here rather than delegated to a package, so the OQ
anchors them to an EXTERNAL PUBLISHED value, not to our own output:

  Hanley JA, McNeil BJ (1982), The meaning and use of the area under a
  receiver operating characteristic (ROC) curve, Radiology 143:29-36.
  Table 1 gives a 5-point diagnostic-confidence rating on 51 abnormal and
  58 normal cases:
      rating      1    2    3    4    5
      normal     33    6    6   11    2     (n = 58)
      abnormal    3    2    2   11   33     (n = 51)
  The paper reports the area under the ROC curve as 0.893.
  jrc_clinical_dx_roc returns 0.8932 on exactly these data.
  (The SE is NOT anchored to the paper: Hanley & McNeil use a binormal-based
  estimator, whereas this script reports the nonparametric DeLong SE. The two
  are different estimators and are not expected to agree.)

The remaining values are properties of the fixed fixtures:

  dx_roc_n200_seed7.csv    m = 80 ref+, n = 120 ref-, continuous, no ties
                           AUC 0.8268, DeLong SE 0.0294, 95% CI
                           (0.7691, 0.8845)
  dx_roc_ties_n26_seed11.csv  m = 12, n = 14, integer scores 1-5, heavy ties
                           AUC 0.5952 — exercises the psi = 0.5 tie kernel;
                           a naive kernel that ignored ties would not return
                           this value.

Two independent checks were run against these expectations outside the
validated environment, and are recorded here as the basis for the values:
  1. The script's own runtime guard recomputes AUC by the definitional
     O(m*n) Mann-Whitney double sum and halts on any disagreement, so every
     run below re-verifies the midrank algorithm against the definition.
  2. The AUC and DeLong variance were compared against pROC 1.19.0.1: AUC
     agreed to 1e-16 and the variance was bit-identical on both the
     continuous and the tie-heavy fixture. pROC is NOT a dependency of this
     project and is not pinned; it was used once as an external oracle.
"""
import glob
import os
import sys
import time

# Force UTF-8 stdout/stderr on Windows (cp1252 cannot encode emoji)
if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if sys.stderr.encoding and sys.stderr.encoding.lower() != "utf-8":
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

from conftest import (run, combined, data, report_float, report_int,
                      run_direct_rscript)

SCRIPT = "jrc_clinical_dx_roc.R"
FIX    = "dx_roc_n200_seed7.csv"
TIES   = "dx_roc_ties_n26_seed11.csv"
HM     = "dx_roc_hanley_mcneil_1982.csv"

# Where the script under test writes its artifacts. The OQ runner sets
# JR_OUT_DIR to this run's own folder; the default matches the scripts'
# own default, so a suite run by hand still looks in ~/Downloads.
DOWNLOADS = os.environ.get("JR_OUT_DIR") or os.path.expanduser("~/Downloads")


def _recent_png(pattern, t_start):
    return [
        f for f in glob.glob(os.path.join(DOWNLOADS, pattern))
        if os.path.getmtime(f) >= t_start - 1.0
    ]


class TestClinicalDxRoc:

    def test_tc_clin_dxroc_001_happy_path_exits_zero(self):
        r = run(SCRIPT, data(FIX))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "ROC analysis" in out
        assert report_int(r, "Reference +") == 80
        assert report_int(r, "Reference -") == 120

    def test_tc_clin_dxroc_002_png_created(self):
        t_start = time.time()
        r = run(SCRIPT, data(FIX))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        recent = _recent_png("*_jrc_clinical_dx_roc.png", t_start)
        assert recent, (
            f"No *_jrc_clinical_dx_roc.png in ~/Downloads/\n"
            f"  DOWNLOADS={DOWNLOADS!r} (exists={os.path.isdir(DOWNLOADS)})\n"
            f"  All matches (any age): "
            f"{glob.glob(os.path.join(DOWNLOADS, '*_jrc_clinical_dx_roc.png'))!r}\n"
            f"  Script output: {combined(r)}"
        )

    def test_tc_clin_dxroc_003_hanley_mcneil_published_auc(self):
        """
        The published external anchor for the base-R AUC implementation.
        Hanley & McNeil (1982) report 0.893 for these data; we return 0.8932.
        """
        r = run(SCRIPT, data(HM))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        assert report_int(r, "Reference +") == 51
        assert report_int(r, "Reference -") == 58
        auc = report_float(r, "AUC")
        assert auc == 0.8932
        # Agrees with the published 0.893 to the paper's 3 decimal places.
        assert round(auc, 3) == 0.893

    def test_tc_clin_dxroc_004_continuous_auc_se_and_ci(self):
        r = run(SCRIPT, data(FIX))
        out = combined(r)
        assert report_float(r, "AUC") == 0.8268
        assert report_float(r, "SE (DeLong)") == 0.0294
        assert "(0.7691, 0.8845)" in out
        assert "DeLong (raw scale)" in out

    def test_tc_clin_dxroc_005_tie_heavy_auc_uses_half_kernel(self):
        r = run(SCRIPT, data(TIES))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        assert report_int(r, "Reference +") == 12
        assert report_int(r, "Reference -") == 14
        # Integer scores 1-5 across 26 subjects: almost every comparison is a
        # tie. 0.5952 is only obtained with the psi = 0.5 tie kernel.
        assert report_float(r, "AUC") == 0.5952

    def test_tc_clin_dxroc_006_youden_cutoff_and_operating_point(self):
        r = run(SCRIPT, data(FIX))
        assert report_float(r, "J") == 0.5125
        assert report_float(r, "Sensitivity") == 0.5875
        assert report_float(r, "Specificity") == 0.9250

    def test_tc_clin_dxroc_007_cutoff_is_observed_value_with_explicit_rule(self):
        r = run(SCRIPT, data(FIX))
        assert "Cutoff         : score >= 2.192 => positive" in combined(r)

    def test_tc_clin_dxroc_008_auc_half_test_reported(self):
        r = run(SCRIPT, data(FIX))
        out = combined(r)
        assert "H0: AUC = 0.5" in out
        assert "z = 11.1017" in out

    def test_tc_clin_dxroc_009_direction_lower_reflects_auc(self):
        higher = report_float(run(SCRIPT, data(FIX)), "AUC")
        lower  = report_float(run(SCRIPT, data(FIX), "--direction", "lower"),
                              "AUC")
        assert higher == 0.8268
        assert lower == 0.1732
        # Reversing the direction reflects the AUC about 0.5.
        assert abs((higher + lower) - 1.0) < 1e-9

    def test_tc_clin_dxroc_010_degenerate_cutoff_reported_as_none(self):
        r = run(SCRIPT, data(FIX), "--direction", "lower")
        out = combined(r)
        assert r.returncode == 0
        # No cutoff beats chance in this direction: must say so rather than
        # print an infinite threshold.
        assert "Cutoff         : none" in out
        assert "Inf" not in out.split("Youden-optimal")[1].split("---")[0]
        assert "AUC < 0.5" in out
        assert "--direction higher" in out

    def test_tc_clin_dxroc_011_logit_ci_differs_and_stays_in_unit_interval(self):
        r = run(SCRIPT, data(FIX), "--ci-method", "logit")
        out = combined(r)
        assert r.returncode == 0
        assert report_float(r, "AUC") == 0.8268     # estimate unchanged
        assert "DeLong (logit-transformed)" in out
        assert "(0.7614, 0.8772)" in out

    def test_tc_clin_dxroc_012_lower_conf_narrows_interval(self):
        r90 = run(SCRIPT, data(FIX), "--conf", "0.90")
        out = combined(r90)
        assert r90.returncode == 0
        assert report_float(r90, "AUC") == 0.8268
        assert "90% CI" in out
        # 95% CI is (0.7691, 0.8845); the 90% CI must sit strictly inside it.
        assert "(0.7784, 0.8752)" in out

    def test_tc_clin_dxroc_013_bad_direction_rejected(self):
        r = run(SCRIPT, data(FIX), "--direction", "sideways")
        assert r.returncode != 0
        assert "--direction must be" in combined(r)

    def test_tc_clin_dxroc_014_missing_column_rejected(self):
        # dx_accuracy fixture has a 'result' column, not 'score'.
        r = run(SCRIPT, data("dx_accuracy_n200_seed42.csv"))
        assert r.returncode != 0
        assert "Missing column(s): score" in combined(r)

    def test_tc_clin_dxroc_015_duplicate_id_rejected(self):
        r = run(SCRIPT, data("dx_dup_id.csv"))
        assert r.returncode != 0
        assert "Duplicate id(s) found" in combined(r)

    def test_tc_clin_dxroc_016_too_few_reference_negative_rejected(self):
        # Fixture is all reference-positive: no negatives to build an ROC
        # against, so the curve is undefined.
        r = run(SCRIPT, data("dx_all_reference_positive.csv"))
        assert r.returncode != 0
        assert "At least 2 reference-negative" in combined(r)

    def test_tc_clin_dxroc_017_direct_rscript_blocked_without_renv(self):
        r = run_direct_rscript("repos/clinical/R/jrc_clinical_dx_roc.R",
                               data(FIX))
        assert r.returncode != 0
        assert "RENV_PATHS_ROOT" in combined(r)
