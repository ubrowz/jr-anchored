"""
OQ test suite — Clinical module: jrc_clinical_dx_compare

Maps to validation plan JR-VP-CLIN-001 (Rev 4):

  TC-CLIN-DXCMP-001  Valid inputs -> exit 0, header + subject counts
  TC-CLIN-DXCMP-002  Two-panel PNG written to the output directory
  TC-CLIN-DXCMP-003  EXTERNAL-ORACLE ANCHOR — per-test AUCs 0.8681 / 0.6670
  TC-CLIN-DXCMP-004  Difference A - B = +0.2011 (95% CI +0.1148, +0.2875)
  TC-CLIN-DXCMP-005  Paired DeLong test z = 4.5640, p = 5.019e-06
  TC-CLIN-DXCMP-006  Between-AUC correlation 0.2468 reported
  TC-CLIN-DXCMP-007  Significant difference stated (test_a higher)
  TC-CLIN-DXCMP-008  --conf 0.90 -> difference CI (+0.1287, +0.2736), tighter
  TC-CLIN-DXCMP-009  --ci-method logit -> per-test CIs differ, stay in (0, 1)
  TC-CLIN-DXCMP-010  --direction lower reflects both AUCs; z sign flips
  TC-CLIN-DXCMP-011  --tests names the two columns explicitly
  TC-CLIN-DXCMP-012  Two test columns auto-inferred when unambiguous
  TC-CLIN-DXCMP-013  Ambiguous columns (3 candidates) -> non-zero exit
  TC-CLIN-DXCMP-014  Named test column absent -> non-zero exit
  TC-CLIN-DXCMP-015  Missing reference column -> non-zero exit
  TC-CLIN-DXCMP-016  Duplicate id -> non-zero exit
  TC-CLIN-DXCMP-017  No reference-negative subjects -> non-zero exit
  TC-CLIN-DXCMP-018  Direct Rscript call without RENV_PATHS_ROOT -> non-zero

The load-bearing cases are TC-003/004/005. The two AUCs, their covariance and
the paired DeLong statistic are implemented in base R here (the placement-value
method of DeLong, DeLong & Clarke-Pearson 1988, Biometrics 44:837-845 — the
method written for exactly this correlated-curve comparison). The acceptance
values are therefore taken from an INDEPENDENT REFERENCE IMPLEMENTATION, not
from our own output: on dx_compare_paired_seed7.csv (70 reference-positive,
100 reference-negative; two correlated tests) pROC 1.19.0.1's
roc.test(method = "delong") returns the same two AUCs, the same z statistic
(4.5640) and the same p value (5.019e-06) — agreeing bit-identically (z to
~3e-15, p to ~6e-20). pROC is NOT a dependency of this project and is not
pinned; it was used once as an external oracle, exactly as for
jrc_clinical_dx_roc. The individual-AUC kernel is additionally the same one
jrc_clinical_dx_roc anchors to the published Hanley & McNeil (1982) value.
"""
import glob
import os
import re
import sys
import time

if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if sys.stderr.encoding and sys.stderr.encoding.lower() != "utf-8":
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

from conftest import run, combined, data, run_direct_rscript

SCRIPT = "jrc_clinical_dx_compare.R"
FIX    = "dx_compare_paired_seed7.csv"

DOWNLOADS = os.environ.get("JR_OUT_DIR") or os.path.expanduser("~/Downloads")


def _recent_png(pattern, t_start):
    return [
        f for f in glob.glob(os.path.join(DOWNLOADS, pattern))
        if os.path.getmtime(f) >= t_start - 1.0
    ]


def _auc(out, which):
    m = re.search(rf"AUC {which} \([^)]*\)\s*:\s*([\d.]+)\s*\(\s*[\d.]+% CI "
                  rf"([\d.]+),\s*([\d.]+)\)", out)
    return tuple(float(x) for x in m.groups()) if m else None


class TestClinicalDxCompare:

    def test_tc_clin_dxcmp_001_happy_path_exits_zero(self):
        r = run(SCRIPT, data(FIX))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Paired ROC comparison" in out
        assert "reference + = 70, reference - = 100" in out

    def test_tc_clin_dxcmp_002_png_created(self):
        t_start = time.time()
        r = run(SCRIPT, data(FIX))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        assert _recent_png("*_jrc_clinical_dx_compare.png", t_start), combined(r)

    def test_tc_clin_dxcmp_003_oracle_per_test_aucs(self):
        r = run(SCRIPT, data(FIX))
        out = combined(r)
        a = _auc(out, "A"); b = _auc(out, "B")
        assert a is not None and b is not None, out
        assert a[0] == 0.8681 and (a[1], a[2]) == (0.8138, 0.9225)
        assert b[0] == 0.6670 and (b[1], b[2]) == (0.5851, 0.7489)

    def test_tc_clin_dxcmp_004_difference_and_ci(self):
        r = run(SCRIPT, data(FIX))
        assert "Difference    : +0.2011  (95% CI +0.1148, +0.2875)" in combined(r)

    def test_tc_clin_dxcmp_005_delong_test(self):
        r = run(SCRIPT, data(FIX))
        out = combined(r)
        m = re.search(r"z = (-?[\d.]+)\s+p = ([\d.eE+-]+)", out)
        assert m, out
        assert float(m.group(1)) == 4.5640
        assert m.group(2) == "5.019e-06"

    def test_tc_clin_dxcmp_006_correlation_reported(self):
        r = run(SCRIPT, data(FIX))
        assert re.search(r"Correlation\s+:\s*0.2468", combined(r))

    def test_tc_clin_dxcmp_007_significance_statement(self):
        r = run(SCRIPT, data(FIX))
        out = combined(r)
        assert "Test test_a has the higher AUC, and the difference is significant" in out

    def test_tc_clin_dxcmp_008_lower_conf_tightens_diff_ci(self):
        r = run(SCRIPT, data(FIX), "--conf", "0.90")
        assert "90% CI +0.1287, +0.2736" in combined(r)

    def test_tc_clin_dxcmp_009_logit_ci_differs_and_in_unit_interval(self):
        r = run(SCRIPT, data(FIX), "--ci-method", "logit")
        out = combined(r)
        assert "DeLong (logit-transformed)" in out
        a = _auc(out, "A")
        assert a[0] == 0.8681                    # estimate unchanged
        assert (a[1], a[2]) == (0.8037, 0.9137)  # differs from raw (0.8138, 0.9225)

    def test_tc_clin_dxcmp_010_direction_lower_reflects_and_flips_z(self):
        r = run(SCRIPT, data(FIX), "--direction", "lower")
        out = combined(r)
        a = _auc(out, "A"); b = _auc(out, "B")
        assert a[0] == 0.1319 and b[0] == 0.3330      # reflected about 0.5-ish
        assert re.search(r"z = -4.5640", out)         # sign flips, |z| unchanged

    def test_tc_clin_dxcmp_011_explicit_tests_flag(self):
        r = run(SCRIPT, data(FIX), "--tests", "test_a,test_b")
        assert r.returncode == 0
        assert "Tests         : A = test_a   vs   B = test_b" in combined(r)

    def test_tc_clin_dxcmp_012_auto_infer_two_columns(self):
        # No --tests: the two non-id/reference columns are used.
        r = run(SCRIPT, data(FIX))
        assert "A = test_a   vs   B = test_b" in combined(r)

    def test_tc_clin_dxcmp_013_ambiguous_columns_rejected(self):
        r = run(SCRIPT, data("dx_compare_three_tests.csv"))
        assert r.returncode != 0
        assert "Could not infer the two test columns" in combined(r)

    def test_tc_clin_dxcmp_014_named_column_absent_rejected(self):
        r = run(SCRIPT, data(FIX), "--tests", "test_a,nosuchcol")
        assert r.returncode != 0
        assert "Test column(s) not found: nosuchcol" in combined(r)

    def test_tc_clin_dxcmp_015_missing_reference_rejected(self):
        # km fixture has id,time,event,group -> no 'reference' column.
        r = run(SCRIPT, data("km_aml_miller1981.csv"))
        assert r.returncode != 0
        assert "Missing column(s): reference" in combined(r)

    def test_tc_clin_dxcmp_016_duplicate_id_rejected(self):
        r = run(SCRIPT, data("dx_compare_dup_id.csv"))
        assert r.returncode != 0
        assert "Duplicate id(s) found" in combined(r)

    def test_tc_clin_dxcmp_017_no_negatives_rejected(self):
        r = run(SCRIPT, data("dx_compare_all_positive.csv"))
        assert r.returncode != 0
        assert "At least 2 reference-negative" in combined(r)

    def test_tc_clin_dxcmp_018_direct_rscript_blocked_without_renv(self):
        r = run_direct_rscript("repos/clinical/R/jrc_clinical_dx_compare.R",
                               data(FIX))
        assert r.returncode != 0
        assert "RENV_PATHS_ROOT" in combined(r)
