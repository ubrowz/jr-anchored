"""
OQ test suite — Clinical module: jrc_clinical_coxph

Maps to validation plan JR-VP-CLIN-001 (Rev 3):

  TC-CLIN-COX-001  Valid inputs -> exit 0, header + subject/event counts
  TC-CLIN-COX-002  PNG (Schoenfeld residual diagnostic) written
  TC-CLIN-COX-003  PUBLISHED ANCHOR — NCCTG lung data (Therneau & Grambsch
                   2000), Surv(time,status) ~ age + sex: sex HR 0.5986
                   (0.4311, 0.8311)
  TC-CLIN-COX-004  PUBLISHED ANCHOR — same model, age HR 1.0172
                   (0.9990, 1.0357)
  TC-CLIN-COX-005  Harrell's concordance 0.6029
  TC-CLIN-COX-006  Global likelihood-ratio chi-square 14.1231, Wald 13.47
  TC-CLIN-COX-007  PH assumption holds on lung (global Schoenfeld p 0.2502)
  TC-CLIN-COX-008  PH assumption VIOLATED on veteran ~ karno (global p 0.0003)
  TC-CLIN-COX-009  Factor covariate: sex_label male vs female HR 1.7007
  TC-CLIN-COX-010  Rows with a missing covariate value are dropped (227/164)
  TC-CLIN-COX-011  --ties breslow -> sex HR 0.5990, differs from efron
  TC-CLIN-COX-012  --conf 0.90 -> tighter sex HR CI (0.4545, 0.7884)
  TC-CLIN-COX-013  Missing covariate column -> non-zero exit
  TC-CLIN-COX-014  --covariates omitted -> non-zero exit
  TC-CLIN-COX-015  Duplicate id -> non-zero exit
  TC-CLIN-COX-016  Fewer than 2 events -> non-zero exit
  TC-CLIN-COX-017  Direct Rscript call without RENV_PATHS_ROOT -> non-zero

The load-bearing cases are TC-003/004/005/006: the Cox partial-likelihood fit
is anchored to the EXTERNAL published NCCTG lung-cancer analysis in Therneau &
Grambsch (2000), Modeling Survival Data — the canonical worked example for
coxph. On Surv(time, status) ~ age + sex (sex coded 1 = male, 2 = female) that
analysis reports a female-vs-male hazard ratio of 0.60 and an age HR of 1.02;
jrc_clinical_coxph returns 0.5986 and 1.0172 on the same 228 patients.

TC-008 anchors the proportional-hazards diagnostic: the Veterans' lung-cancer
data with the Karnofsky score is the textbook PH violation (Therneau &
Grambsch), and the script must flag it.
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

from conftest import run, combined, data, report_int, run_direct_rscript

SCRIPT  = "jrc_clinical_coxph.R"
LUNG    = "coxph_lung_therneau.csv"
VETERAN = "coxph_veteran_karno.csv"

DOWNLOADS = os.environ.get("JR_OUT_DIR") or os.path.expanduser("~/Downloads")


def _recent_png(pattern, t_start):
    return [
        f for f in glob.glob(os.path.join(DOWNLOADS, pattern))
        if os.path.getmtime(f) >= t_start - 1.0
    ]


def _hr_row(out, term):
    """Parse 'term HR lower upper p' -> (HR, lower, upper, p)."""
    m = re.search(rf"^{re.escape(term)}\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.eE+-]+)",
                  out, re.M)
    return tuple(float(x) for x in m.groups()) if m else None


class TestClinicalCoxph:

    def test_tc_clin_cox_001_happy_path_exits_zero(self):
        r = run(SCRIPT, data(LUNG), "--covariates", "age,sex")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Cox proportional-hazards regression" in out
        assert report_int(r, "Subjects") == 228
        assert "Events: 165" in out

    def test_tc_clin_cox_002_png_created(self):
        t_start = time.time()
        r = run(SCRIPT, data(LUNG), "--covariates", "age,sex")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        assert _recent_png("*_jrc_clinical_coxph.png", t_start), combined(r)

    def test_tc_clin_cox_003_published_sex_hr(self):
        r = run(SCRIPT, data(LUNG), "--covariates", "age,sex")
        hr = _hr_row(combined(r), "sex")
        assert hr is not None, combined(r)
        assert hr[0] == 0.5986 and hr[1] == 0.4311 and hr[2] == 0.8311

    def test_tc_clin_cox_004_published_age_hr(self):
        r = run(SCRIPT, data(LUNG), "--covariates", "age,sex")
        hr = _hr_row(combined(r), "age")
        assert hr[0] == 1.0172 and hr[1] == 0.9990 and hr[2] == 1.0357

    def test_tc_clin_cox_005_concordance(self):
        r = run(SCRIPT, data(LUNG), "--covariates", "age,sex")
        m = re.search(r"Concordance \(C\)\s*:\s*([\d.]+)", combined(r))
        assert m and float(m.group(1)) == 0.6029

    def test_tc_clin_cox_006_global_tests(self):
        r = run(SCRIPT, data(LUNG), "--covariates", "age,sex")
        out = combined(r)
        assert re.search(r"Likelihood ratio : chisq = 14.1231", out)
        assert re.search(r"Wald\s+: chisq = 13.4700", out)

    def test_tc_clin_cox_007_ph_assumption_ok(self):
        r = run(SCRIPT, data(LUNG), "--covariates", "age,sex")
        out = combined(r)
        assert "PH assumption OK" in out
        assert re.search(r"global p = 0.2502", out)

    def test_tc_clin_cox_008_ph_assumption_violated(self):
        r = run(SCRIPT, data(VETERAN), "--covariates", "karno")
        out = combined(r)
        assert r.returncode == 0
        assert "PH assumption VIOLATED" in out
        assert re.search(r"global p = 0.000316", out)

    def test_tc_clin_cox_009_factor_covariate(self):
        r = run(SCRIPT, data(LUNG), "--covariates", "sex_label")
        hr = _hr_row(combined(r), "sex_labelmale")
        assert hr is not None, combined(r)
        # male vs female (reference) = 1 / 0.5986 = 1.7007
        assert hr[0] == 1.7007

    def test_tc_clin_cox_010_missing_covariate_rows_dropped(self):
        # ph_ecog has one NA -> that row is dropped before fitting.
        r = run(SCRIPT, data(LUNG), "--covariates", "age,ph_ecog")
        out = combined(r)
        assert report_int(r, "Subjects") == 227
        assert "Dropped rows  : 1" in out

    def test_tc_clin_cox_011_breslow_ties_differ(self):
        r = run(SCRIPT, data(LUNG), "--covariates", "age,sex", "--ties", "breslow")
        hr = _hr_row(combined(r), "sex")
        assert hr[0] == 0.5990          # efron gives 0.5986

    def test_tc_clin_cox_012_lower_conf_tightens_hr_ci(self):
        r = run(SCRIPT, data(LUNG), "--covariates", "age,sex", "--conf", "0.90")
        hr = _hr_row(combined(r), "sex")
        assert hr[0] == 0.5986
        assert hr[1] == 0.4545 and hr[2] == 0.7884   # tighter than 95%

    def test_tc_clin_cox_013_missing_covariate_column_rejected(self):
        r = run(SCRIPT, data(LUNG), "--covariates", "nosuchcol")
        assert r.returncode != 0
        assert "Missing column(s)" in combined(r)

    def test_tc_clin_cox_014_covariates_required(self):
        r = run(SCRIPT, data(LUNG))
        assert r.returncode != 0
        assert "--covariates is required" in combined(r)

    def test_tc_clin_cox_015_duplicate_id_rejected(self):
        r = run(SCRIPT, data("km_dup_id.csv"), "--covariates", "time")
        assert r.returncode != 0
        assert "Duplicate id(s) found" in combined(r)

    def test_tc_clin_cox_016_too_few_events_rejected(self):
        r = run(SCRIPT, data("coxph_few_events.csv"), "--covariates", "age")
        assert r.returncode != 0
        assert "Fewer than 2 events" in combined(r)

    def test_tc_clin_cox_017_direct_rscript_blocked_without_renv(self):
        r = run_direct_rscript("repos/clinical/R/jrc_clinical_coxph.R",
                               data(LUNG), "--covariates", "age,sex")
        assert r.returncode != 0
        assert "RENV_PATHS_ROOT" in combined(r)
