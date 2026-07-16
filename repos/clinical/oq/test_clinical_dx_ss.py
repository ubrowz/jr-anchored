"""
OQ test suite — Clinical module: jrc_clinical_dx_ss

Maps to validation plan JR-VP-CLIN-001 (Rev 2) as follows:

  TC-CLIN-DXSS-001  Precision valid inputs -> exit 0, report header present
  TC-CLIN-DXSS-002  Precision numeric (Buderer 1996 worked example):
                    sens 0.90, spec 0.95, W 0.05, prev 0.10
                    -> n ref+ 139, n ref- 73, N total 1383
  TC-CLIN-DXSS-003  Hypothesis numeric: sens 0.90 vs goal 0.80, spec 0.95 vs
                    goal 0.90, power 0.80, alpha 0.025 1-sided, prev 0.10
                    -> n ref+ 108, n ref- 239, N total 1075
  TC-CLIN-DXSS-004  Binding arm identified as sensitivity at low prevalence
  TC-CLIN-DXSS-005  Rarer prevalence raises N (monotone), same arm sizes
  TC-CLIN-DXSS-006  --sensitivity -> 5-row N-vs-prevalence table
  TC-CLIN-DXSS-007  --dropout 0.10 on TC-003 -> ENROLL 1195
  TC-CLIN-DXSS-008  Precision defaults to 2-sided z; hypothesis to 1-sided
  TC-CLIN-DXSS-009  Precision without --halfwidth -> non-zero exit
  TC-CLIN-DXSS-010  Hypothesis without --sens-goal -> non-zero exit
  TC-CLIN-DXSS-011  --sens-goal >= --sens-expected -> non-zero exit
  TC-CLIN-DXSS-012  --prevalence out of range -> non-zero exit
  TC-CLIN-DXSS-013  --method bogus -> non-zero exit
  TC-CLIN-DXSS-014  Direct Rscript call without RENV_PATHS_ROOT -> non-zero

Numeric references — computed independently from the formulas, z from R
qnorm(). Per-arm sizes, then Buderer's prevalence step
N = max(n_pos/P, n_neg/(1-P)):

  TC-002 (precision, z = qnorm(0.975) = 1.959964, z^2 = 3.841459):
    n_pos = z^2 * 0.90*0.10 / 0.05^2 = 3.841459 * 0.09 / 0.0025 = 138.29 -> 139
    n_neg = z^2 * 0.95*0.05 / 0.05^2 = 3.841459 * 0.0475 / 0.0025 = 72.99 -> 73
    N     = max(138.29/0.10, 72.99/0.90) = max(1382.93, 81.10) = 1382.93 -> 1383
    The reference-positive arm binds, which is Buderer's point: at 10%
    prevalence you must enrol ~1383 to accumulate ~138 positives.

  TC-003 (hypothesis, z_a = qnorm(0.975) = 1.959964, z_b = qnorm(0.80)
          = 0.8416212):
    n_pos = (1.959964*sqrt(0.80*0.20) + 0.8416212*sqrt(0.90*0.10))^2
            / (0.90-0.80)^2
          = (0.7839856 + 0.2524864)^2 / 0.01 = 1.0743... / 0.01
          = 107.43 -> 108
    n_neg = (1.959964*sqrt(0.90*0.10) + 0.8416212*sqrt(0.95*0.05))^2
            / (0.95-0.90)^2
          = (0.5879892 + 0.1833876)^2 / 0.0025 = 0.5950... / 0.0025
          = 238.02 -> 239
    N     = max(107.43/0.10, 238.02/0.90) = max(1074.3, 264.5) -> 1075

  TC-007: enrolled = ceiling(1075 / 0.90) = 1195
"""
import sys

# Force UTF-8 stdout/stderr on Windows (cp1252 cannot encode emoji)
if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if sys.stderr.encoding and sys.stderr.encoding.lower() != "utf-8":
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

from conftest import run, combined, report_int, run_direct_rscript

SCRIPT = "jrc_clinical_dx_ss.R"

PREC = ["--method", "precision", "--sens-expected", "0.90",
        "--spec-expected", "0.95", "--halfwidth", "0.05",
        "--prevalence", "0.10"]
HYP  = ["--method", "hypothesis", "--sens-expected", "0.90",
        "--spec-expected", "0.95", "--sens-goal", "0.80",
        "--spec-goal", "0.90", "--power", "0.80", "--alpha", "0.025",
        "--sides", "1", "--prevalence", "0.10"]


class TestClinicalDxSS:

    def test_tc_clin_dxss_001_precision_happy_path_exits_zero(self):
        r = run(SCRIPT, *PREC)
        assert r.returncode == 0
        out = combined(r)
        assert "Clinical sample size" in out
        assert "diagnostic accuracy" in out

    def test_tc_clin_dxss_002_precision_numeric_buderer(self):
        r = run(SCRIPT, *PREC)
        assert r.returncode == 0
        assert report_int(r, "n reference +") == 139
        assert report_int(r, "n reference -") == 73
        assert report_int(r, "N TOTAL") == 1383

    def test_tc_clin_dxss_003_hypothesis_numeric(self):
        r = run(SCRIPT, *HYP)
        assert r.returncode == 0
        assert report_int(r, "n reference +") == 108
        assert report_int(r, "n reference -") == 239
        assert report_int(r, "N TOTAL") == 1075

    def test_tc_clin_dxss_004_binding_arm_is_sensitivity_at_low_prevalence(self):
        r = run(SCRIPT, *PREC)
        assert "Binding arm    : sensitivity (reference-positive)" in combined(r)

    def test_tc_clin_dxss_005_rarer_prevalence_raises_total(self):
        base = report_int(run(SCRIPT, *PREC), "N TOTAL")
        rare = run(SCRIPT, "--method", "precision", "--sens-expected", "0.90",
                   "--spec-expected", "0.95", "--halfwidth", "0.05",
                   "--prevalence", "0.05")
        # Arm requirements do not depend on prevalence; only enrolment does.
        assert report_int(rare, "n reference +") == 139
        assert report_int(rare, "N TOTAL") > base
        assert report_int(rare, "N TOTAL") == 2766        # 138.29/0.05 -> 2766

    def test_tc_clin_dxss_006_sensitivity_table_five_rows(self):
        r = run(SCRIPT, *PREC, "--sensitivity")
        out = combined(r)
        assert r.returncode == 0
        assert "<- assumed" in out
        # prevalence x {0.5, 0.75, 1.0, 1.5, 2.0} = 0.05 ... 0.20 -> 5 rows
        rows = [l for l in out.splitlines()
                if l.strip().startswith("0.") and "prevalence" not in l]
        assert len(rows) == 5

    def test_tc_clin_dxss_007_dropout_inflation(self):
        r = run(SCRIPT, *HYP, "--dropout", "0.10")
        assert r.returncode == 0
        assert "ENROLL 1195 subjects" in combined(r)

    def test_tc_clin_dxss_008_sides_default_differs_by_method(self):
        # A CI half-width is inherently two-sided.
        assert "two-sided, z = 1.9600" in combined(run(SCRIPT, *PREC))
        # A performance-goal test defaults to one-sided.
        r = run(SCRIPT, "--method", "hypothesis", "--sens-expected", "0.90",
                "--spec-expected", "0.95", "--sens-goal", "0.80",
                "--spec-goal", "0.90", "--prevalence", "0.10")
        assert "1-sided" in combined(r)

    def test_tc_clin_dxss_009_precision_requires_halfwidth(self):
        r = run(SCRIPT, "--method", "precision", "--sens-expected", "0.90",
                "--spec-expected", "0.95", "--prevalence", "0.10")
        assert r.returncode != 0
        assert "requires --halfwidth" in combined(r)

    def test_tc_clin_dxss_010_hypothesis_requires_sens_goal(self):
        r = run(SCRIPT, "--method", "hypothesis", "--sens-expected", "0.90",
                "--spec-expected", "0.95", "--spec-goal", "0.90",
                "--prevalence", "0.10")
        assert r.returncode != 0
        assert "requires --sens-goal" in combined(r)

    def test_tc_clin_dxss_011_goal_not_below_expected_rejected(self):
        r = run(SCRIPT, "--method", "hypothesis", "--sens-expected", "0.90",
                "--spec-expected", "0.95", "--sens-goal", "0.95",
                "--spec-goal", "0.90", "--prevalence", "0.10")
        assert r.returncode != 0
        assert "--sens-goal must be strictly less than" in combined(r)

    def test_tc_clin_dxss_012_prevalence_out_of_range_rejected(self):
        r = run(SCRIPT, "--method", "precision", "--sens-expected", "0.90",
                "--spec-expected", "0.95", "--halfwidth", "0.05",
                "--prevalence", "1.2")
        assert r.returncode != 0
        assert "--prevalence" in combined(r)

    def test_tc_clin_dxss_013_bad_method_rejected(self):
        r = run(SCRIPT, "--method", "bogus")
        assert r.returncode != 0
        assert "--method must be one of" in combined(r)

    def test_tc_clin_dxss_014_direct_rscript_blocked_without_renv(self):
        r = run_direct_rscript("repos/clinical/R/jrc_clinical_dx_ss.R", *PREC)
        assert r.returncode != 0
        assert "RENV_PATHS_ROOT" in combined(r)
