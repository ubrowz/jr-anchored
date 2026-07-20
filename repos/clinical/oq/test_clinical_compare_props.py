"""
OQ test suite — Clinical module: jrc_clinical_compare_props

Maps to JR-VP-CLIN-001 (Rev 5).

  TC-CLIN-CPROP-001  Valid inputs -> exit 0, header, contingency table
  TC-CLIN-CPROP-002  CLOSED-FORM ANCHOR — chi-square (Yates) 5.6201, p 0.01776
  TC-CLIN-CPROP-003  Fisher's exact p 0.01715
  TC-CLIN-CPROP-004  Risk difference -0.1500 (95% CI -0.2639, -0.0361)
  TC-CLIN-CPROP-005  Risk ratio 0.5000 (95% CI 0.2872, 0.8704)
  TC-CLIN-CPROP-006  Odds ratio 0.4118 (95% CI 0.2053, 0.8258)
  TC-CLIN-CPROP-007  --no-correction -> uncorrected chi-square 6.4516
  TC-CLIN-CPROP-008  --reference treated -> OR reciprocal 2.4286
  TC-CLIN-CPROP-009  Auto-detected event level (yes)
  TC-CLIN-CPROP-010  Missing required column -> non-zero exit
  TC-CLIN-CPROP-011  Duplicate id -> non-zero exit
  TC-CLIN-CPROP-012  Fewer than two groups -> non-zero exit
  TC-CLIN-CPROP-013  --event absent from data -> non-zero exit
  TC-CLIN-CPROP-014  Direct Rscript without RENV_PATHS_ROOT -> non-zero

The load-bearing cases are TC-004/005/006: the three effect measures are
CLOSED-FORM quantities, hand-verifiable on the 2x2 table
(treated 15/85, control 30/70, event = yes):
  RD = 15/100 - 30/100 = -0.15
  RR = 0.15 / 0.30 = 0.50
  OR = (15*70)/(85*30) = 1050/2550 = 0.4118
with Wald (RD) and Woolf-log (RR, OR) intervals. chi-square and Fisher are
computed by base R (chisq.test, fisher.test); this suite confirms the script
reports both the tests and the hand-derived effect measures correctly.
"""
import re
import sys

if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from conftest import run, combined, data, run_direct_rscript

SCRIPT = "jrc_clinical_compare_props.R"
FIX    = "props_2x2_constructed.csv"


class TestClinicalCompareProps:

    def test_tc_clin_cprop_001_happy_path(self):
        r = run(SCRIPT, data(FIX))
        assert r.returncode == 0, combined(r)
        out = combined(r)
        assert "Comparison of a categorical outcome between groups" in out
        assert "Contingency table" in out

    def test_tc_clin_cprop_002_chisq_yates(self):
        r = run(SCRIPT, data(FIX))
        assert re.search(r"Chi-square \(Yates\)\s*:\s*X2 = 5.6201\s+df = 1\s+p = 0.01776",
                         combined(r))

    def test_tc_clin_cprop_003_fisher(self):
        r = run(SCRIPT, data(FIX))
        assert re.search(r"Fisher's exact test\s+p = 0.01715", combined(r))

    def test_tc_clin_cprop_004_risk_difference(self):
        r = run(SCRIPT, data(FIX))
        assert "Risk difference : -0.1500  (95% CI -0.2639, -0.0361)" in combined(r)

    def test_tc_clin_cprop_005_risk_ratio(self):
        r = run(SCRIPT, data(FIX))
        assert "Risk ratio      : 0.5000  (95% CI 0.2872, 0.8704)" in combined(r)

    def test_tc_clin_cprop_006_odds_ratio(self):
        r = run(SCRIPT, data(FIX))
        assert "Odds ratio      : 0.4118  (95% CI 0.2053, 0.8258)" in combined(r)

    def test_tc_clin_cprop_007_no_correction(self):
        r = run(SCRIPT, data(FIX), "--no-correction")
        assert re.search(r"X2 = 6.4516\s+df = 1\s+p = 0.01109", combined(r))

    def test_tc_clin_cprop_008_reference_flips_or(self):
        r = run(SCRIPT, data(FIX), "--reference", "treated")
        assert "Odds ratio      : 2.4286  (95% CI 1.2110, 4.8703)" in combined(r)

    def test_tc_clin_cprop_009_event_autodetected(self):
        r = run(SCRIPT, data(FIX))
        assert "event = 'yes'" in combined(r)

    def test_tc_clin_cprop_010_missing_column(self):
        r = run(SCRIPT, data("means_sleep_student1908.csv"))  # no 'outcome'
        assert r.returncode != 0
        assert "Missing column(s)" in combined(r)

    def test_tc_clin_cprop_011_duplicate_id(self):
        r = run(SCRIPT, data("props_dup_id.csv"))
        assert r.returncode != 0
        assert "Duplicate id(s) found" in combined(r)

    def test_tc_clin_cprop_012_one_group(self):
        r = run(SCRIPT, data("props_one_group.csv"))
        assert r.returncode != 0
        assert "At least two groups" in combined(r)

    def test_tc_clin_cprop_013_bad_event(self):
        r = run(SCRIPT, data(FIX), "--event", "maybe")
        assert r.returncode != 0
        assert "not an outcome level" in combined(r)

    def test_tc_clin_cprop_014_direct_rscript_blocked(self):
        r = run_direct_rscript("repos/clinical/R/jrc_clinical_compare_props.R",
                               data(FIX))
        assert r.returncode != 0
        assert "RENV_PATHS_ROOT" in combined(r)
