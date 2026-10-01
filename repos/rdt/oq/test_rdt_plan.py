"""
OQ test suite — RDT module: jrc_rdt_plan

Maps to validation plan JR-VP-RDT-001 as follows:

  TC-RDT-PLAN-001  Bogey mode exits 0, "Binomial" in output
  TC-RDT-PLAN-002  Weibayes mode exits 0, "Weibayes" in output
  TC-RDT-PLAN-003  Bogey k=0 → n=45  (R=0.95, C=0.90, TL=5000)
  TC-RDT-PLAN-004  Weibayes k=0 beta=2 AF=1 → n=45 (AF=1 → beta-independent)
  TC-RDT-PLAN-005  Weibayes beta=2 AF=2 → n=12
  TC-RDT-PLAN-006  k_allowed=1 → k=1 row marked as plan, n=77 present (exact binomial)
  TC-RDT-PLAN-007  --help exits 0 with "Usage" in output
  TC-RDT-PLAN-008  Beta sensitivity table shown when accel_factor > 1
  TC-RDT-PLAN-009  PNG written to ~/Downloads/
  TC-RDT-PLAN-010  --reliability out of range → non-zero exit
  TC-RDT-PLAN-011  --confidence out of range → non-zero exit
  TC-RDT-PLAN-012  Missing required arg (--confidence) → non-zero exit
  TC-RDT-PLAN-013  Bypass protection: direct Rscript without RENV_PATHS_ROOT
"""
import sys

# Force UTF-8 stdout/stderr on Windows (cp1252 cannot encode emoji)
if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if sys.stderr.encoding and sys.stderr.encoding.lower() != "utf-8":
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

import glob
import math
import os
import subprocess
import time

from conftest import PROJECT_ROOT, MODULE_ROOT, run, combined, data, RSCRIPT_BIN


# Where the script under test writes its artifacts. The OQ runner sets
# JR_OUT_DIR to this run's own folder; the default matches the scripts'
# own default, so a suite run by hand still looks in ~/Downloads.
DOWNLOADS = os.environ.get("JR_OUT_DIR") or os.path.expanduser("~/Downloads")


def _recent_png(pattern, t_start):
    return [
        f for f in glob.glob(os.path.join(DOWNLOADS, pattern))
        if os.path.getmtime(f) >= t_start - 1.0
    ]


class TestRdtPlan:

    def test_tc_rdt_plan_001_binomial_happy_path(self):
        """
        TC-RDT-PLAN-001:
        Bogey mode (no --beta): exits 0, "Binomial" in output.
        """
        r = run("jrc_rdt_plan.R",
                "--reliability", "0.95", "--confidence", "0.90", "--target_life", "5000")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        assert "Binomial" in combined(r), f"Expected 'Binomial' in output:\n{combined(r)}"

    def test_tc_rdt_plan_002_weibayes_happy_path(self):
        """
        TC-RDT-PLAN-002:
        Weibayes mode (--beta 2.0): exits 0, "Weibayes" in output.
        """
        r = run("jrc_rdt_plan.R",
                "--reliability", "0.95", "--confidence", "0.90", "--target_life", "5000",
                "--beta", "2.0")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        assert "Weibayes" in combined(r), f"Expected 'Weibayes' in output:\n{combined(r)}"

    def test_tc_rdt_plan_003_bogey_k0_n45(self):
        """
        TC-RDT-PLAN-003:
        Bogey k=0 → n=45 for R=0.95, C=0.90, TL=5000.

        Independent reference (pure Python, no R):
          n = ceiling(qchisq(0.90, 2) / (2 * (-log(0.95))))
            = ceiling(4.60517 / (2 * 0.051293))
            = ceiling(4.60517 / 0.102587)
            = ceiling(44.89)
            = 45
          Equivalent exact formula: ceiling(log(0.10) / log(0.95)) = ceiling(44.89) = 45
        """
        n_ref = math.ceil(math.log(0.10) / math.log(0.95))
        assert n_ref == 45, f"Reference computation error: got {n_ref}"

        r = run("jrc_rdt_plan.R",
                "--reliability", "0.95", "--confidence", "0.90", "--target_life", "5000")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "n = 45" in out, f"Expected 'n = 45' in output:\n{out}"

    def test_tc_rdt_plan_004_weibayes_k0_af1_n45(self):
        """
        TC-RDT-PLAN-004:
        Weibayes k=0 beta=2 AF=1 → n=45.

        At AF=1: AF^beta = 1^2 = 1 for any beta, so formula reduces to Bogey.
        Same n=45 as Bogey regardless of beta value.
        """
        r = run("jrc_rdt_plan.R",
                "--reliability", "0.95", "--confidence", "0.90", "--target_life", "5000",
                "--beta", "2.0")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "n = 45" in out, f"Expected 'n = 45' in output (AF=1 → beta-independent):\n{out}"

    def test_tc_rdt_plan_005_weibayes_af2_beta2_n12(self):
        """
        TC-RDT-PLAN-005:
        Weibayes beta=2 AF=2 → n=12.

        Independent reference (pure Python, no R):
          n = ceiling(qchisq(0.90, 2) / (2 * (-log(0.95)) * 2^2))
            = ceiling(4.60517 / (0.102587 * 4))
            = ceiling(4.60517 / 0.410349)
            = ceiling(11.22)
            = 12
          Equivalent: ceiling(log(0.10) / (log(0.95) * 4)) = 12
        """
        n_ref = math.ceil(math.log(0.10) / (math.log(0.95) * 4))
        assert n_ref == 12, f"Reference computation error: got {n_ref}"

        r = run("jrc_rdt_plan.R",
                "--reliability", "0.95", "--confidence", "0.90", "--target_life", "5000",
                "--beta", "2.0", "--accel_factor", "2.0")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "n = 12" in out, f"Expected 'n = 12' in output:\n{out}"

    def test_tc_rdt_plan_006_k_allowed_1(self):
        """
        TC-RDT-PLAN-006:
        k_allowed=1 → plan row is k=1 with n=77 (Bogey mode, exact binomial).

        Independent reference (pure Python, no R):
          Bogey mode sizes with the same exact (Clopper-Pearson) criterion that
          jrc_rdt_verify applies: the smallest n with
              P(X <= k | n, p = 1 - R) <= 1 - C
          (equivalent to 1 - qbeta(C, k+1, n-k) >= R).
          R = 0.95, C = 0.90, k = 1:
              n = 76 → P = 0.1014 > 0.10   (insufficient)
              n = 77 → P = 0.0973 <= 0.10  (sufficient)  → n = 77
          The chi-squared/Poisson approximation used previously gave 76, which
          then FAILED jrc_rdt_verify with exactly one failure.
        """
        def binom_cdf(k, n, p):
            return sum(math.comb(n, i) * p**i * (1 - p)**(n - i) for i in range(k + 1))

        n_ref = 2
        while binom_cdf(1, n_ref, 0.05) > 0.10:
            n_ref += 1
        assert n_ref == 77, f"Reference computation error: got {n_ref}"
        assert binom_cdf(1, 76, 0.05) > 0.10, "Reference: n=76 must be insufficient"

        r = run("jrc_rdt_plan.R",
                "--reliability", "0.95", "--confidence", "0.90", "--target_life", "5000",
                "--k_allowed", "1")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "n = 77" in out, f"Expected 'n = 77' (k=1 bogey, exact binomial) in output:\n{out}"
        assert "<- plan" in out, f"Expected plan marker '<- plan' in output:\n{out}"

    def test_tc_rdt_plan_007_help_exits_zero(self):
        """
        TC-RDT-PLAN-007:
        --help exits 0 with "Usage" in output.
        """
        r = run("jrc_rdt_plan.R", "--help")
        assert r.returncode == 0, f"Expected exit 0 for --help:\n{combined(r)}"
        assert "Usage" in combined(r), f"Expected 'Usage' in --help output:\n{combined(r)}"

    def test_tc_rdt_plan_008_beta_sensitivity_table(self):
        """
        TC-RDT-PLAN-008:
        Beta sensitivity table is shown when accel_factor > 1.
        """
        r = run("jrc_rdt_plan.R",
                "--reliability", "0.95", "--confidence", "0.90", "--target_life", "5000",
                "--beta", "2.0", "--accel_factor", "2.0")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Beta Sensitivity" in out, \
            f"Expected 'Beta Sensitivity' section in output:\n{out}"

    def test_tc_rdt_plan_009_png_created(self):
        """
        TC-RDT-PLAN-009:
        PNG matching *_jrc_rdt_plan.png written to ~/Downloads/.
        """
        t_start = time.time()
        r = run("jrc_rdt_plan.R",
                "--reliability", "0.95", "--confidence", "0.90", "--target_life", "5000")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        recent = _recent_png("*_jrc_rdt_plan.png", t_start)
        assert recent, (
            f"No *_jrc_rdt_plan.png found in ~/Downloads/ after plan run\n"
            f"  DOWNLOADS={DOWNLOADS!r} (exists={os.path.isdir(DOWNLOADS)})\n"
            f"  All matches (any age): {glob.glob(os.path.join(DOWNLOADS, '*_jrc_rdt_plan.png'))!r}\n"
            f"  Script output: {combined(r)}"
        )

    def test_tc_rdt_plan_010_reliability_out_of_range(self):
        """
        TC-RDT-PLAN-010:
        --reliability=1.5 (out of (0,1)) → non-zero exit.
        """
        r = run("jrc_rdt_plan.R",
                "--reliability", "1.5", "--confidence", "0.90", "--target_life", "5000")
        assert r.returncode != 0, \
            f"Expected non-zero exit for reliability=1.5:\n{combined(r)}"

    def test_tc_rdt_plan_011_confidence_out_of_range(self):
        """
        TC-RDT-PLAN-011:
        --confidence=0 (out of (0,1)) → non-zero exit.
        """
        r = run("jrc_rdt_plan.R",
                "--reliability", "0.95", "--confidence", "0", "--target_life", "5000")
        assert r.returncode != 0, \
            f"Expected non-zero exit for confidence=0:\n{combined(r)}"

    def test_tc_rdt_plan_012_missing_required_arg(self):
        """
        TC-RDT-PLAN-012:
        Missing --confidence → non-zero exit with error mentioning the missing arg.
        """
        r = run("jrc_rdt_plan.R",
                "--reliability", "0.95", "--target_life", "5000")
        assert r.returncode != 0, \
            f"Expected non-zero exit when --confidence is missing:\n{combined(r)}"

    def test_tc_rdt_plan_013_bypass_protection(self):
        """
        TC-RDT-PLAN-013:
        Calling jrc_rdt_plan.R directly via Rscript without RENV_PATHS_ROOT
        must exit non-zero and mention RENV_PATHS_ROOT in the error output.
        """
        script = os.path.join(MODULE_ROOT, "R", "jrc_rdt_plan.R")
        env = {k: v for k, v in os.environ.items() if k != "RENV_PATHS_ROOT"}
        result = subprocess.run(
            [RSCRIPT_BIN, script,
             "--reliability", "0.95", "--confidence", "0.90", "--target_life", "5000"],
            capture_output=True,
            encoding="utf-8",
            env=env,
            cwd=PROJECT_ROOT,
        )
        assert result.returncode != 0, \
            "Expected non-zero exit when called without RENV_PATHS_ROOT"
        out = (result.stdout or "") + (result.stderr or "")
        assert "RENV_PATHS_ROOT" in out, \
            f"Expected 'RENV_PATHS_ROOT' in error output:\n{out}"
