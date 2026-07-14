"""
OQ test suite — Clinical module: jrc_clinical_ss_props

Maps to validation plan JR-VP-CLIN-001 as follows:

  TC-CLIN-PROPS-001  Superiority valid inputs -> exit 0, report header present
  TC-CLIN-PROPS-002  Superiority numeric: pc=0.70, pt=0.85, power=0.80,
                     alpha=0.05 2-sided -> n=118/arm, 236 total
  TC-CLIN-PROPS-003  Non-inferiority numeric: pc=0.85, margin=0.10,
                     power=0.80, alpha=0.025 1-sided -> n=201/arm, 402 total;
                     'assumed equal to control' note present
  TC-CLIN-PROPS-004  Equivalence numeric: pc=0.80, margin=0.15, power=0.80,
                     alpha=0.05 1-sided (TOST) -> n=122/arm, 244 total
  TC-CLIN-PROPS-005  Superiority without --p-treat -> non-zero exit + message
  TC-CLIN-PROPS-006  Superiority with p-treat == p-control -> non-zero exit
  TC-CLIN-PROPS-007  Non-inferiority without --margin -> non-zero exit
  TC-CLIN-PROPS-008  --p-control 1.2 (out of range) -> non-zero exit
  TC-CLIN-PROPS-009  --sensitivity -> 5-row n-vs-p-control table
  TC-CLIN-PROPS-010  Dropout 0.10 on TC-003 -> ENROLL 224 + 224 = 448
  TC-CLIN-PROPS-011  Direct Rscript call without RENV_PATHS_ROOT ->
                     non-zero exit + RENV_PATHS_ROOT in output

Numeric references — independently computed from the normal-approximation
(unpooled variance) risk-difference formulas (Chow, Shao & Wang 2008, ch. 4),
with V = pt(1-pt)/k + pc(1-pc), z from R qnorm():

  TC-002: V = 0.85*0.15 + 0.70*0.30 = 0.3375, d = 0.15
          n/arm = ceiling( 0.3375 * (qnorm(0.975)+qnorm(0.80))^2 / 0.15^2 )
                = ceiling( 0.3375 * 7.848886 / 0.0225 )            = 118
  TC-003: V = 2 * 0.85*0.15 = 0.255 (pt defaults to pc), d = 0
          n/arm = ceiling( 0.255 * 7.848886 / 0.10^2 )             = 201
  TC-004: V = 2 * 0.80*0.20 = 0.32, d = 0
          n/arm = ceiling( 0.32 * (qnorm(0.95)+qnorm(0.90))^2 / 0.15^2 )
                = ceiling( 0.32 * 8.563852 / 0.0225 )              = 122
  TC-010: enrolled/arm = ceiling( 201 / 0.90 )                     = 224
"""
import sys

# Force UTF-8 stdout/stderr on Windows (cp1252 cannot encode emoji)
if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if sys.stderr.encoding and sys.stderr.encoding.lower() != "utf-8":
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

from conftest import run, combined, report_int, run_direct_rscript

SCRIPT = "jrc_clinical_ss_props.R"

SUP = ["--framework", "superiority", "--power", "0.80", "--alpha", "0.05",
       "--sides", "2", "--p-control", "0.70", "--p-treat", "0.85"]
NI  = ["--framework", "non_inferiority", "--power", "0.80", "--alpha", "0.025",
       "--sides", "1", "--p-control", "0.85", "--margin", "0.10"]
EQ  = ["--framework", "equivalence", "--power", "0.80", "--alpha", "0.05",
       "--sides", "1", "--p-control", "0.80", "--margin", "0.15"]


class TestClinicalSSProps:

    def test_tc_clin_props_001_superiority_happy_path_exits_zero(self):
        r = run(SCRIPT, *SUP)
        assert r.returncode == 0
        assert "Clinical sample size" in combined(r)
        assert "binary endpoint" in combined(r)

    def test_tc_clin_props_002_superiority_numeric(self):
        r = run(SCRIPT, *SUP)
        assert report_int(r, "n treatment") == 118
        assert report_int(r, "n control") == 118
        assert report_int(r, "n TOTAL") == 236

    def test_tc_clin_props_003_non_inferiority_numeric_default_ptreat(self):
        r = run(SCRIPT, *NI)
        assert r.returncode == 0
        assert "assumed equal to control" in combined(r)
        assert report_int(r, "n treatment") == 201
        assert report_int(r, "n control") == 201
        assert report_int(r, "n TOTAL") == 402

    def test_tc_clin_props_004_equivalence_numeric(self):
        r = run(SCRIPT, *EQ)
        assert r.returncode == 0
        assert "equivalence (TOST)" in combined(r)
        assert report_int(r, "n TOTAL") == 244

    def test_tc_clin_props_005_superiority_requires_ptreat(self):
        r = run(SCRIPT, "--framework", "superiority", "--power", "0.80",
                "--alpha", "0.05", "--sides", "2", "--p-control", "0.70")
        assert r.returncode != 0
        assert "requires --p-treat" in combined(r)

    def test_tc_clin_props_006_superiority_equal_rates_rejected(self):
        r = run(SCRIPT, "--framework", "superiority", "--power", "0.80",
                "--alpha", "0.05", "--sides", "2", "--p-control", "0.70",
                "--p-treat", "0.70")
        assert r.returncode != 0
        assert "different from p-control" in combined(r)

    def test_tc_clin_props_007_non_inferiority_requires_margin(self):
        r = run(SCRIPT, "--framework", "non_inferiority", "--power", "0.80",
                "--alpha", "0.025", "--sides", "1", "--p-control", "0.85")
        assert r.returncode != 0
        assert "requires --margin" in combined(r)

    def test_tc_clin_props_008_p_control_out_of_range(self):
        r = run(SCRIPT, "--framework", "non_inferiority", "--power", "0.80",
                "--alpha", "0.025", "--sides", "1", "--p-control", "1.2",
                "--margin", "0.10")
        assert r.returncode != 0
        assert "--p-control" in combined(r)

    def test_tc_clin_props_009_sensitivity_table_five_rows(self):
        r = run(SCRIPT, *EQ, "--sensitivity")
        out = combined(r)
        assert r.returncode == 0
        assert "Sensitivity" in out
        assert "<- assumed" in out
        rows = [l for l in out.splitlines()
                if l.strip().startswith("0.") and "p control" not in l]
        # pc x {0.8, 0.9, 1.0, 1.1, 1.2} = 0.64 ... 0.96, all in (0,1) -> 5 rows
        assert len(rows) == 5

    def test_tc_clin_props_010_dropout_inflation(self):
        r = run(SCRIPT, *NI, "--dropout", "0.10")
        assert r.returncode == 0
        assert "ENROLL 224 + 224 = 448" in combined(r)

    def test_tc_clin_props_011_direct_rscript_blocked_without_renv(self):
        r = run_direct_rscript("repos/clinical/R/jrc_clinical_ss_props.R", *SUP)
        assert r.returncode != 0
        assert "RENV_PATHS_ROOT" in combined(r)
