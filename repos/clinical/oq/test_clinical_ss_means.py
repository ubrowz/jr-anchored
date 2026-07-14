"""
OQ test suite — Clinical module: jrc_clinical_ss_means

Maps to validation plan JR-VP-CLIN-001 as follows:

  TC-CLIN-MEANS-001  Superiority valid inputs -> exit 0, report header present
  TC-CLIN-MEANS-002  Superiority numeric: sd=10, delta=5, power=0.80,
                     alpha=0.05 2-sided -> n=63/arm, 126 total
  TC-CLIN-MEANS-003  Alpha/sides line shows z = 1.9600 for 0.05 two-sided
  TC-CLIN-MEANS-004  Non-inferiority numeric: sd=8, margin=4, power=0.90,
                     alpha=0.025 1-sided -> n=85/arm, 170 total
  TC-CLIN-MEANS-005  Dropout 0.15 on TC-004 -> ENROLL 100 + 100 = 200
  TC-CLIN-MEANS-006  Equivalence numeric: sd=10, margin=5, power=0.80,
                     alpha=0.05 1-sided (TOST) -> n=69/arm, 138 total
  TC-CLIN-MEANS-007  Allocation 2:1 on TC-002 -> n treat=95, n control=48
  TC-CLIN-MEANS-008  --sensitivity -> 5-row n-vs-SD table; n scales with SD^2
                     (totals 82 at SD=8 and 182 at SD=12 for TC-002 inputs)
  TC-CLIN-MEANS-009  Superiority without --delta -> non-zero exit + message
  TC-CLIN-MEANS-010  Non-inferiority without --margin -> non-zero exit
  TC-CLIN-MEANS-011  Equivalence with |delta| >= margin -> non-zero exit
  TC-CLIN-MEANS-012  --power 1.5 -> non-zero exit
  TC-CLIN-MEANS-013  Unknown flag -> non-zero exit + 'Unknown argument'
  TC-CLIN-MEANS-014  Direct Rscript call without RENV_PATHS_ROOT ->
                     non-zero exit + RENV_PATHS_ROOT in output

Numeric references — independently computed from the normal-approximation
two-sample formulas (Chow, Shao & Wang 2008, ch. 3), z from R qnorm():

  TC-002: n/arm = ceiling( 2 * 10^2 * (qnorm(0.975) + qnorm(0.80))^2 / 5^2 )
                = ceiling( 8 * (1.959964 + 0.841621)^2 )            = 63
  TC-004: n/arm = ceiling( 2 *  8^2 * (qnorm(0.975) + qnorm(0.90))^2 / 4^2 )
                = ceiling( 8 * (1.959964 + 1.281552)^2 )            = 85
          (alpha 0.025 one-sided -> z_(1-0.025) = qnorm(0.975))
  TC-005: enrolled/arm = ceiling( 85 / (1 - 0.15) )                 = 100
  TC-006: n/arm = ceiling( 2 * 10^2 * (qnorm(0.95) + qnorm(0.90))^2 / 5^2 )
                = ceiling( 8 * (1.644854 + 1.281552)^2 )            = 69
          (equivalence beta term is z_(1-(1-power)/2) = qnorm(0.90))
  TC-007: n_control = ceiling( (1 + 1/2) * 100 * 2.801585^2 / 25 )  = 48
          n_treat   = ceiling( 2 * (1 + 1/2) * 100 * 2.801585^2 / 25 ) = 95
  TC-008: totals at SD 8 / 12 = 82 / 182 (n proportional to SD^2):
          SD=8:  total = 2 * ceiling( 2 * 64 * 7.848886 / 25 ) = 2*41 =  82
          SD=12: total = 2 * ceiling( 2 * 144 * 7.848886 / 25 ) = 2*91 = 182
"""
import sys

# Force UTF-8 stdout/stderr on Windows (cp1252 cannot encode emoji)
if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if sys.stderr.encoding and sys.stderr.encoding.lower() != "utf-8":
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

from conftest import run, combined, report_int, run_direct_rscript

SCRIPT = "jrc_clinical_ss_means.R"

SUP = ["--framework", "superiority", "--power", "0.80", "--alpha", "0.05",
       "--sides", "2", "--sd", "10", "--delta", "5"]
NI  = ["--framework", "non_inferiority", "--power", "0.90", "--alpha", "0.025",
       "--sides", "1", "--sd", "8", "--margin", "4"]
EQ  = ["--framework", "equivalence", "--power", "0.80", "--alpha", "0.05",
       "--sides", "1", "--sd", "10", "--margin", "5"]


class TestClinicalSSMeans:

    def test_tc_clin_means_001_superiority_happy_path_exits_zero(self):
        r = run(SCRIPT, *SUP)
        assert r.returncode == 0
        assert "Clinical sample size" in combined(r)
        assert "continuous endpoint" in combined(r)

    def test_tc_clin_means_002_superiority_numeric(self):
        r = run(SCRIPT, *SUP)
        assert report_int(r, "n treatment") == 63
        assert report_int(r, "n control") == 63
        assert report_int(r, "n TOTAL") == 126

    def test_tc_clin_means_003_two_sided_z_value(self):
        r = run(SCRIPT, *SUP)
        assert "2-sided" in combined(r)
        assert "1.9600" in combined(r)

    def test_tc_clin_means_004_non_inferiority_numeric(self):
        r = run(SCRIPT, *NI)
        assert r.returncode == 0
        assert "non-inferiority" in combined(r)
        assert report_int(r, "n treatment") == 85
        assert report_int(r, "n control") == 85
        assert report_int(r, "n TOTAL") == 170

    def test_tc_clin_means_005_dropout_inflation(self):
        r = run(SCRIPT, *NI, "--dropout", "0.15")
        assert r.returncode == 0
        assert "ENROLL 100 + 100 = 200" in combined(r)

    def test_tc_clin_means_006_equivalence_numeric(self):
        r = run(SCRIPT, *EQ)
        assert r.returncode == 0
        assert "equivalence (TOST)" in combined(r)
        assert report_int(r, "n TOTAL") == 138

    def test_tc_clin_means_007_allocation_two_to_one(self):
        r = run(SCRIPT, *SUP, "--ratio", "2")
        assert r.returncode == 0
        assert report_int(r, "n treatment") == 95
        assert report_int(r, "n control") == 48

    def test_tc_clin_means_008_sensitivity_table_scales_with_sd_squared(self):
        r = run(SCRIPT, *SUP, "--sensitivity")
        out = combined(r)
        assert r.returncode == 0
        assert "Sensitivity" in out
        rows = [l for l in out.splitlines()
                if l.strip() and l.strip()[0].isdigit() and "<- assumed" not in l]
        # SD 8, 9, 11, 12 rows plus the assumed row = 5 scenario lines
        assert "<- assumed" in out
        assert len(rows) == 4
        assert any(l.strip().startswith("8") and l.strip().endswith("82") for l in rows)
        assert any(l.strip().startswith("12") and l.strip().endswith("182") for l in rows)

    def test_tc_clin_means_009_superiority_requires_delta(self):
        r = run(SCRIPT, "--framework", "superiority", "--power", "0.80",
                "--alpha", "0.05", "--sides", "2", "--sd", "10")
        assert r.returncode != 0
        assert "requires --delta" in combined(r)

    def test_tc_clin_means_010_non_inferiority_requires_margin(self):
        r = run(SCRIPT, "--framework", "non_inferiority", "--power", "0.90",
                "--alpha", "0.025", "--sides", "1", "--sd", "8")
        assert r.returncode != 0
        assert "requires --margin" in combined(r)

    def test_tc_clin_means_011_equivalence_delta_inside_margin(self):
        r = run(SCRIPT, "--framework", "equivalence", "--power", "0.80",
                "--alpha", "0.05", "--sides", "1", "--sd", "10",
                "--margin", "5", "--delta", "5")
        assert r.returncode != 0
        assert "|delta| < margin" in combined(r)

    def test_tc_clin_means_012_power_out_of_range(self):
        r = run(SCRIPT, "--framework", "superiority", "--power", "1.5",
                "--alpha", "0.05", "--sides", "2", "--sd", "10", "--delta", "5")
        assert r.returncode != 0
        assert "--power" in combined(r)

    def test_tc_clin_means_013_unknown_flag_rejected(self):
        r = run(SCRIPT, *SUP, "--bogus", "1")
        assert r.returncode != 0
        assert "Unknown argument" in combined(r)

    def test_tc_clin_means_014_direct_rscript_blocked_without_renv(self):
        r = run_direct_rscript("repos/clinical/R/jrc_clinical_ss_means.R", *SUP)
        assert r.returncode != 0
        assert "RENV_PATHS_ROOT" in combined(r)
