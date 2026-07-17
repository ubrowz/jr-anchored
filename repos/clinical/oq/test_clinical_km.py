"""
OQ test suite — Clinical module: jrc_clinical_km

Maps to validation plan JR-VP-CLIN-001 (Rev 3):

  TC-CLIN-KM-001  Valid inputs -> exit 0, header + subject/event counts
  TC-CLIN-KM-002  PNG written to the output directory
  TC-CLIN-KM-003  PUBLISHED ANCHOR — Miller (1981) aml data: median survival
                  31 (maintained) vs 23 (nonmaintained)
  TC-CLIN-KM-004  PUBLISHED ANCHOR — aml log-rank chi-square 3.3964, df 1,
                  p 0.0653 (Miller 1981; matches survival::survdiff)
  TC-CLIN-KM-005  aml log-rank observed/expected: 7/10.69 and 11/7.31
  TC-CLIN-KM-006  Ungrouped overall median 27 (95% CI 18, 45)
  TC-CLIN-KM-007  --time-point 30 grouped: S(30) 0.6136 and 0.2917
  TC-CLIN-KM-008  --conf 0.90 -> 90% median CI (18, 43), tighter than 95%
  TC-CLIN-KM-009  --rho 1 (Peto/Gehan-Wilcoxon) -> chi-square 2.7793, != log-rank
  TC-CLIN-KM-010  --event-positive custom label
  TC-CLIN-KM-011  yes/no event labels accepted
  TC-CLIN-KM-012  Median CI upper bound reported as NA when not reached
  TC-CLIN-KM-013  Missing required column -> non-zero exit
  TC-CLIN-KM-014  Duplicate id -> non-zero exit
  TC-CLIN-KM-015  All rows censored -> non-zero exit
  TC-CLIN-KM-016  --group with a single distinct value -> non-zero exit
  TC-CLIN-KM-017  Unrecognised event labels -> non-zero exit
  TC-CLIN-KM-018  Non-positive time -> non-zero exit
  TC-CLIN-KM-019  Direct Rscript call without RENV_PATHS_ROOT -> non-zero

The load-bearing cases are TC-003/004/005: the Kaplan-Meier estimate and
log-rank test are anchored to an EXTERNAL PUBLISHED source, not to our own
output. Miller RG (1981), Survival Analysis, uses the acute-myelogenous-
leukaemia maintenance trial (the `aml` / `leukemia` dataset shipped with the
survival package): 11 maintained and 12 non-maintained patients, medians 31
and 23 weeks, log-rank chi-square 3.4 on 1 df (p = 0.07). jrc_clinical_km
reproduces these on exactly those data.

Remaining values are properties of the fixed fixtures, computed by the
validated survival package (Therneau) and checked here for regression.
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

SCRIPT = "jrc_clinical_km.R"
AML    = "km_aml_miller1981.csv"

DOWNLOADS = os.environ.get("JR_OUT_DIR") or os.path.expanduser("~/Downloads")


def _recent_png(pattern, t_start):
    return [
        f for f in glob.glob(os.path.join(DOWNLOADS, pattern))
        if os.path.getmtime(f) >= t_start - 1.0
    ]


class TestClinicalKm:

    def test_tc_clin_km_001_happy_path_exits_zero(self):
        r = run(SCRIPT, data(AML), "--group", "group")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Kaplan-Meier survival analysis" in out
        assert report_int(r, "Subjects") == 23

    def test_tc_clin_km_002_png_created(self):
        t_start = time.time()
        r = run(SCRIPT, data(AML), "--group", "group")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        recent = _recent_png("*_jrc_clinical_km.png", t_start)
        assert recent, (
            f"No *_jrc_clinical_km.png in {DOWNLOADS!r}\n{combined(r)}")

    def test_tc_clin_km_003_published_medians(self):
        r = run(SCRIPT, data(AML), "--group", "group")
        out = combined(r)
        # Miller (1981): maintained median 31, nonmaintained 23.
        assert re.search(r"Maintained\s+n = 11.*?Median survival : 31", out, re.S)
        assert re.search(r"Nonmaintained\s+n = 12.*?Median survival : 23", out, re.S)

    def test_tc_clin_km_004_published_logrank(self):
        r = run(SCRIPT, data(AML), "--group", "group")
        out = combined(r)
        m = re.search(r"Chi-square = ([\d.]+)\s+df = (\d+)\s+p = ([\d.]+)", out)
        assert m, f"log-rank line not found:\n{out}"
        assert float(m.group(1)) == 3.3964      # rounds to the published 3.4
        assert int(m.group(2)) == 1
        assert round(float(m.group(3)), 2) == 0.07

    def test_tc_clin_km_005_logrank_observed_expected(self):
        r = run(SCRIPT, data(AML), "--group", "group")
        out = combined(r)
        assert re.search(r"Maintained\s+observed = 7\s+expected = 10.69", out)
        assert re.search(r"Nonmaintained\s+observed = 11\s+expected = 7.31", out)

    def test_tc_clin_km_006_ungrouped_overall_median(self):
        r = run(SCRIPT, data(AML))
        out = combined(r)
        assert re.search(r"Overall\s+n = 23", out)
        assert "Median survival : 27  (95% CI 18, 45)" in out

    def test_tc_clin_km_007_survival_at_timepoint(self):
        r = run(SCRIPT, data(AML), "--group", "group", "--time-point", "30")
        out = combined(r)
        assert "Survival at t = 30" in out
        assert re.search(r"Maintained\s+S\(30\) = 0.6136", out)
        assert re.search(r"Nonmaintained\s+S\(30\) = 0.2917", out)

    def test_tc_clin_km_008_lower_conf_tightens_median_ci(self):
        r = run(SCRIPT, data(AML), "--conf", "0.90")
        out = combined(r)
        assert "90% CI 18, 43" in out          # tighter than the 95% (18, 45)

    def test_tc_clin_km_009_rho_weighted_differs_from_logrank(self):
        r = run(SCRIPT, data(AML), "--group", "group", "--rho", "1")
        out = combined(r)
        assert "Peto" in out
        m = re.search(r"Chi-square = ([\d.]+)", out)
        assert float(m.group(1)) == 2.7793     # != the log-rank 3.3964

    def test_tc_clin_km_010_event_positive_override(self):
        # km_yesno uses yes/no; naming the event explicitly must also work.
        r = run(SCRIPT, data("km_yesno.csv"), "--event-positive", "yes")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        assert report_int(r, "Subjects") == 6

    def test_tc_clin_km_011_yesno_labels_autodetected(self):
        r = run(SCRIPT, data("km_yesno.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        assert "Events: 3" in combined(r)

    def test_tc_clin_km_012_median_ci_na_when_not_reached(self):
        # In the aml maintained arm the upper median CI is not reached -> NA.
        r = run(SCRIPT, data(AML), "--group", "group")
        assert re.search(r"Median survival : 31\s+\(95% CI 18,\s+NA", combined(r))

    def test_tc_clin_km_013_missing_column_rejected(self):
        r = run(SCRIPT, data("dx_accuracy_n200_seed42.csv"))  # no time/event
        assert r.returncode != 0
        assert "Missing column(s)" in combined(r)

    def test_tc_clin_km_014_duplicate_id_rejected(self):
        r = run(SCRIPT, data("km_dup_id.csv"))
        assert r.returncode != 0
        assert "Duplicate id(s) found" in combined(r)

    def test_tc_clin_km_015_all_censored_rejected(self):
        r = run(SCRIPT, data("km_all_censored.csv"))
        assert r.returncode != 0
        assert "No events observed" in combined(r)

    def test_tc_clin_km_016_single_group_rejected(self):
        r = run(SCRIPT, data("km_one_group.csv"), "--group", "arm")
        assert r.returncode != 0
        assert "only one distinct value" in combined(r)

    def test_tc_clin_km_017_bad_event_labels_rejected(self):
        r = run(SCRIPT, data("km_bad_event.csv"))
        assert r.returncode != 0
        assert "does not recognise" in combined(r)

    def test_tc_clin_km_018_nonpositive_time_rejected(self):
        r = run(SCRIPT, data("km_neg_time.csv"))
        assert r.returncode != 0
        assert "strictly positive" in combined(r)

    def test_tc_clin_km_019_direct_rscript_blocked_without_renv(self):
        r = run_direct_rscript("repos/clinical/R/jrc_clinical_km.R", data(AML))
        assert r.returncode != 0
        assert "RENV_PATHS_ROOT" in combined(r)
