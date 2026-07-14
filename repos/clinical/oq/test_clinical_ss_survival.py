"""
OQ test suite — Clinical module: jrc_clinical_ss_survival

Maps to validation plan JR-VP-CLIN-001 as follows:

  TC-CLIN-SURV-001  Superiority valid inputs -> exit 0, report header present
  TC-CLIN-SURV-002  Superiority numeric: HR=0.70, power=0.80, alpha=0.05
                    2-sided, event-prob=0.6 -> 247 events, n=206/arm, 412 total
  TC-CLIN-SURV-003  Non-inferiority numeric: true HR=1.0, margin=1.3,
                    power=0.80, alpha=0.025 1-sided, event-prob=0.5 ->
                    457 events, n=457/arm, 914 total
  TC-CLIN-SURV-004  --framework equivalence -> non-zero exit + 'not offered'
  TC-CLIN-SURV-005  Superiority with --hr 1 -> non-zero exit
  TC-CLIN-SURV-006  Non-inferiority with --margin <= 1 -> non-zero exit
  TC-CLIN-SURV-007  Non-inferiority with --hr >= --margin -> non-zero exit
  TC-CLIN-SURV-008  Missing --event-prob -> non-zero exit
  TC-CLIN-SURV-009  --sensitivity -> 5-row n-vs-event-prob table
  TC-CLIN-SURV-010  Dropout 0.20 on TC-002 -> ENROLL 258 + 258 = 516
  TC-CLIN-SURV-011  Direct Rscript call without RENV_PATHS_ROOT ->
                    non-zero exit + RENV_PATHS_ROOT in output

Numeric references — independently computed from the Schoenfeld (1983)
events formula, E = (1+k)^2/k * (z_a + z_b)^2 / (log effect)^2, k = 1,
z from R qnorm():

  TC-002: E = ceiling( 4 * (qnorm(0.975)+qnorm(0.80))^2 / log(0.70)^2 )
            = ceiling( 4 * 7.848886 / 0.127178 )                   = 247
          n/arm = ceiling( (246.86/0.6) / 2 )                      = 206
  TC-003: E = ceiling( 4 * 7.848886 / log(1.3)^2 )
            = ceiling( 31.395544 / 0.068835 )                      = 457
          (alpha 0.025 one-sided -> z_(1-0.025) = qnorm(0.975);
           log effect = log(margin) - log(true HR) = log(1.3))
          n/arm = ceiling( (456.10/0.5) / 2 )                      = 457
  TC-010: enrolled/arm = ceiling( 206 / 0.80 )                     = 258
"""
import sys

# Force UTF-8 stdout/stderr on Windows (cp1252 cannot encode emoji)
if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if sys.stderr.encoding and sys.stderr.encoding.lower() != "utf-8":
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

from conftest import run, combined, report_int, run_direct_rscript

SCRIPT = "jrc_clinical_ss_survival.R"

SUP = ["--framework", "superiority", "--power", "0.80", "--alpha", "0.05",
       "--sides", "2", "--hr", "0.70", "--event-prob", "0.6"]
NI  = ["--framework", "non_inferiority", "--power", "0.80", "--alpha", "0.025",
       "--sides", "1", "--hr", "1.0", "--margin", "1.3", "--event-prob", "0.5"]


class TestClinicalSSSurvival:

    def test_tc_clin_surv_001_superiority_happy_path_exits_zero(self):
        r = run(SCRIPT, *SUP)
        assert r.returncode == 0
        assert "Clinical sample size" in combined(r)
        assert "time-to-event endpoint" in combined(r)

    def test_tc_clin_surv_002_superiority_numeric(self):
        r = run(SCRIPT, *SUP)
        assert report_int(r, "Events required") == 247
        assert report_int(r, "n treatment") == 206
        assert report_int(r, "n control") == 206
        assert report_int(r, "n TOTAL") == 412

    def test_tc_clin_surv_003_non_inferiority_numeric(self):
        r = run(SCRIPT, *NI)
        assert r.returncode == 0
        assert "non-inferiority" in combined(r)
        assert report_int(r, "Events required") == 457
        assert report_int(r, "n TOTAL") == 914

    def test_tc_clin_surv_004_equivalence_not_offered(self):
        r = run(SCRIPT, "--framework", "equivalence", "--power", "0.80",
                "--alpha", "0.05", "--sides", "1", "--hr", "1.0",
                "--event-prob", "0.5")
        assert r.returncode != 0
        assert "not offered" in combined(r)

    def test_tc_clin_surv_005_superiority_hr_one_rejected(self):
        r = run(SCRIPT, "--framework", "superiority", "--power", "0.80",
                "--alpha", "0.05", "--sides", "2", "--hr", "1",
                "--event-prob", "0.6")
        assert r.returncode != 0
        assert "different from 1" in combined(r)

    def test_tc_clin_surv_006_ni_margin_must_exceed_one(self):
        r = run(SCRIPT, "--framework", "non_inferiority", "--power", "0.80",
                "--alpha", "0.025", "--sides", "1", "--hr", "1.0",
                "--margin", "0.9", "--event-prob", "0.5")
        assert r.returncode != 0
        assert "--margin" in combined(r)

    def test_tc_clin_surv_007_ni_hr_inside_margin(self):
        r = run(SCRIPT, "--framework", "non_inferiority", "--power", "0.80",
                "--alpha", "0.025", "--sides", "1", "--hr", "1.4",
                "--margin", "1.3", "--event-prob", "0.5")
        assert r.returncode != 0
        assert "--hr < --margin" in combined(r)

    def test_tc_clin_surv_008_event_prob_required(self):
        r = run(SCRIPT, "--framework", "superiority", "--power", "0.80",
                "--alpha", "0.05", "--sides", "2", "--hr", "0.70")
        assert r.returncode != 0
        assert "--event-prob" in combined(r)

    def test_tc_clin_surv_009_sensitivity_table_five_rows(self):
        r = run(SCRIPT, *SUP, "--sensitivity")
        out = combined(r)
        assert r.returncode == 0
        assert "Sensitivity" in out
        assert "<- assumed" in out
        rows = [l for l in out.splitlines()
                if l.strip().startswith("0.") and "P(event)" not in l]
        # PE x {0.8, 0.9, 1.0, 1.1, 1.2} = 0.48 ... 0.72, all in (0,1] -> 5 rows
        assert len(rows) == 5

    def test_tc_clin_surv_010_dropout_inflation(self):
        r = run(SCRIPT, *SUP, "--dropout", "0.20")
        assert r.returncode == 0
        assert "ENROLL 258 + 258 = 516" in combined(r)

    def test_tc_clin_surv_011_direct_rscript_blocked_without_renv(self):
        r = run_direct_rscript("repos/clinical/R/jrc_clinical_ss_survival.R", *SUP)
        assert r.returncode != 0
        assert "RENV_PATHS_ROOT" in combined(r)
