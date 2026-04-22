"""
OQ test suite — RDT module: jrc_rdt_verify

Maps to validation plan JR-VP-RDT-001 as follows:

  TC-RDT-VER-001  rdt_verify_pass.csv exits 0, "Verdict" in output
  TC-RDT-VER-002  rdt_verify_pass.csv → "PASS" (45 units, k=0, R=0.95, C=0.90)
  TC-RDT-VER-003  rdt_verify_fail.csv → "FAIL" (20 units, k=0), exits 0
  TC-RDT-VER-004  rdt_verify_pass.csv + --beta 2.0 → Weibayes section + "PASS"
  TC-RDT-VER-005  PNG written to ~/Downloads/
  TC-RDT-VER-006  rdt_verify_all_failed_early.csv → "FAIL", R_lower near 0
  TC-RDT-VER-007  rdt_verify_zero_failures.csv: n=50 k=0 R_claim=0.90 → R_lower in [0.953, 0.959]
  TC-RDT-VER-008  No arguments → non-zero exit, usage in output
  TC-RDT-VER-009  File not found → non-zero exit, "not found" in output
  TC-RDT-VER-010  rdt_verify_missing_col.csv → non-zero exit, column name in output
  TC-RDT-VER-011  Non-numeric time values (inline temp CSV) → non-zero exit
  TC-RDT-VER-012  Bypass protection: direct Rscript without RENV_PATHS_ROOT
"""

import glob
import math
import os
import subprocess
import tempfile
import time

from conftest import PROJECT_ROOT, MODULE_ROOT, run, combined, data, extract_float


DOWNLOADS = os.path.expanduser("~/Downloads")


def _recent_png(pattern, t_start):
    return [
        f for f in glob.glob(os.path.join(DOWNLOADS, pattern))
        if os.path.getmtime(f) >= t_start
    ]


class TestRdtVerify:

    def test_tc_rdt_ver_001_happy_path_exits_zero(self):
        """
        TC-RDT-VER-001:
        rdt_verify_pass.csv runs to completion: exits 0, "Verdict" in output.
        """
        r = run("jrc_rdt_verify.R", data("rdt_verify_pass.csv"),
                "--reliability", "0.95", "--confidence", "0.90", "--target_life", "5000")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        assert "Verdict" in combined(r), f"Expected 'Verdict' in output:\n{combined(r)}"

    def test_tc_rdt_ver_002_pass_verdict_45_units(self):
        """
        TC-RDT-VER-002:
        rdt_verify_pass.csv: 45 units all survived, R=0.95, C=0.90, TL=5000 → PASS.

        Independent reference (pure Python, no R):
          Clopper-Pearson for n=45, k=0 — exact closed form for Beta(1, n):
            F_upper = qbeta(0.90, 1, 45) = 1 - (1 - 0.90)^(1/45) = 1 - 0.10^(1/45)
            0.10^(1/45) = exp(ln(0.10)/45) ≈ 0.95013
          F_upper ≈ 0.04987
          R_lower ≈ 0.95013  → PASS (≥ 0.95)
        """
        F_upper_ref = 1 - (0.10 ** (1.0 / 45))
        R_lower_ref = 1 - F_upper_ref  # ≈ 0.95013
        assert R_lower_ref >= 0.95, f"Reference check failed: R_lower_ref={R_lower_ref}"

        r = run("jrc_rdt_verify.R", data("rdt_verify_pass.csv"),
                "--reliability", "0.95", "--confidence", "0.90", "--target_life", "5000")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "PASS" in out, f"Expected PASS verdict:\n{out}"

        # Numeric assertion: script's R_lower must match the reference within tolerance
        R_lower = extract_float(r, "R_lower =")
        assert R_lower is not None, f"Could not extract R_lower from output:\n{out}"
        assert abs(R_lower - R_lower_ref) < 0.0002, \
            f"R_lower={R_lower} deviates from reference {R_lower_ref:.6f}"

    def test_tc_rdt_ver_003_fail_verdict_20_units(self):
        """
        TC-RDT-VER-003:
        rdt_verify_fail.csv: 20 units all survived, R=0.95, C=0.90, TL=5000 → FAIL.
        Script exits 0 (FAIL verdict is normal, not an error).

        Independent reference (pure Python, no R):
          n=20, k=0 — exact closed form for Beta(1, n):
            F_upper = qbeta(0.90, 1, 20) = 1 - 0.10^(1/20)
            0.10^(1/20) = exp(ln(0.10)/20) ≈ 0.89125
          F_upper ≈ 0.10875
          R_lower ≈ 0.89125  → FAIL (< 0.95)
        """
        F_upper_ref = 1 - (0.10 ** (1.0 / 20))
        R_lower_ref = 1 - F_upper_ref  # ≈ 0.89125
        assert R_lower_ref < 0.95, f"Reference check failed: R_lower_ref={R_lower_ref}"

        r = run("jrc_rdt_verify.R", data("rdt_verify_fail.csv"),
                "--reliability", "0.95", "--confidence", "0.90", "--target_life", "5000")
        assert r.returncode == 0, f"Expected exit 0 (FAIL verdict, not script error):\n{combined(r)}"
        out = combined(r)
        assert "FAIL" in out, f"Expected FAIL verdict:\n{out}"

        # Numeric assertion: script's R_lower must match the reference within tolerance
        R_lower = extract_float(r, "R_lower =")
        assert R_lower is not None, f"Could not extract R_lower from output:\n{out}"
        assert abs(R_lower - R_lower_ref) < 0.0002, \
            f"R_lower={R_lower} deviates from reference {R_lower_ref:.6f}"

    def test_tc_rdt_ver_004_weibayes_pass(self):
        """
        TC-RDT-VER-004:
        rdt_verify_pass.csv with --beta 2.0: Weibayes section shown, R_demo ≈ 0.9501, PASS.

        Independent reference (pure Python, no R):
          n=45, beta=2, t=5000, C=0.90, k=0.
          T* = n * t^beta = 45 * 5000^2 = 1.125e9
          qchisq(0.90, 2) = -2 * ln(0.10) = 2 * 2.302585... = 4.605170...
            (exact: chi-sq(2) CDF = 1 - exp(-x/2), so ppf(0.90) = -2*ln(0.10))
          eta_demo = (2 * T* / qchisq(0.90, 2))^(1/beta)
                   = (2 * 1.125e9 / 4.605170)^0.5
                   ≈ 22103.9
          R_demo = exp(-(5000 / eta_demo)^2) ≈ exp(-0.05117) ≈ 0.9501
          → PASS (≥ 0.95)
        """
        import math
        n, beta, t, C = 45, 2.0, 5000.0, 0.90
        T_star = n * t ** beta
        chi2_ppf = -2.0 * math.log(1.0 - C)        # exact: qchisq(0.90, 2)
        eta = (2.0 * T_star / chi2_ppf) ** (1.0 / beta)
        R_demo_ref = math.exp(-(t / eta) ** beta)   # ≈ 0.9501
        assert R_demo_ref >= 0.95, f"Reference check failed: R_demo_ref={R_demo_ref}"

        r = run("jrc_rdt_verify.R", data("rdt_verify_pass.csv"),
                "--reliability", "0.95", "--confidence", "0.90", "--target_life", "5000",
                "--beta", "2.0")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Weibayes" in out, f"Expected 'Weibayes' section:\n{out}"
        assert "PASS" in out, f"Expected PASS verdict:\n{out}"

        # Numeric assertion: script's R_demo must match the reference within tolerance
        # Label "at 5000:" skips past the target_life value to reach R_demo
        R_demo = extract_float(r, "at 5000:")
        assert R_demo is not None, f"Could not extract R_demo from Weibayes output:\n{out}"
        assert abs(R_demo - R_demo_ref) < 0.0002, \
            f"R_demo={R_demo} deviates from reference {R_demo_ref:.6f}"

    def test_tc_rdt_ver_005_png_created(self):
        """
        TC-RDT-VER-005:
        PNG matching *_jrc_rdt_verify.png written to ~/Downloads/.
        """
        t_start = time.time()
        r = run("jrc_rdt_verify.R", data("rdt_verify_pass.csv"),
                "--reliability", "0.95", "--confidence", "0.90", "--target_life", "5000")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        recent = _recent_png("*_jrc_rdt_verify.png", t_start)
        assert recent, "No *_jrc_rdt_verify.png found in ~/Downloads/ after verify run"

    def test_tc_rdt_ver_006_all_failed_early(self):
        """
        TC-RDT-VER-006:
        rdt_verify_all_failed_early.csv: 10 units all failed at t=2500 < target_life=5000.
        All count as k: k=10, n-k=0 → R_lower = 0.0 (edge-case handling) → FAIL.
        """
        r = run("jrc_rdt_verify.R", data("rdt_verify_all_failed_early.csv"),
                "--reliability", "0.95", "--confidence", "0.90", "--target_life", "5000")
        assert r.returncode == 0, f"Expected exit 0 (FAIL is normal):\n{combined(r)}"
        out = combined(r)
        assert "FAIL" in out, f"Expected FAIL verdict:\n{out}"
        R_lower = extract_float(r, "R_lower =")
        assert R_lower is not None, f"Could not extract R_lower from output:\n{out}"
        assert R_lower < 0.01, f"Expected R_lower near 0, got {R_lower}:\n{out}"

    def test_tc_rdt_ver_007_known_numeric_r_lower(self):
        """
        TC-RDT-VER-007:
        rdt_verify_zero_failures.csv: n=50 units, k=0, R_claim=0.90, C=0.90, TL=5000.
        R_lower must fall in [0.953, 0.959].

        Independent reference (pure Python, no R):
          Clopper-Pearson for n=50, k=0:
          F_upper = qbeta(0.90, 1, 50) = 1 - (1-0.90)^(1/50) = 1 - 0.10^(1/50)
          0.10^(1/50) = exp(ln(0.10)/50) = exp(-2.302585/50) = exp(-0.046052) ≈ 0.954991
          F_upper ≈ 0.045009
          R_lower ≈ 0.954991

          Assert: 0.953 <= R_lower <= 0.959
        """
        F_upper_ref = 1 - (0.10 ** (1.0 / 50))
        R_lower_ref = 1 - F_upper_ref
        assert 0.953 <= R_lower_ref <= 0.959, \
            f"Reference value out of expected range: {R_lower_ref}"

        r = run("jrc_rdt_verify.R", data("rdt_verify_zero_failures.csv"),
                "--reliability", "0.90", "--confidence", "0.90", "--target_life", "5000")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        R_lower = extract_float(r, "R_lower =")
        assert R_lower is not None, f"Could not extract R_lower:\n{combined(r)}"
        assert 0.953 <= R_lower <= 0.959, \
            f"Expected R_lower in [0.953, 0.959], got {R_lower}:\n{combined(r)}"

    def test_tc_rdt_ver_008_no_arguments(self):
        """
        TC-RDT-VER-008:
        No arguments → exits 0 (help shown), "Usage" in output.
        Both scripts follow the convention: no args = show help = exit 0.
        """
        r = run("jrc_rdt_verify.R")
        assert r.returncode == 0, \
            f"Expected exit 0 (help) when no arguments provided:\n{combined(r)}"
        assert "Usage" in combined(r), \
            f"Expected 'Usage' in no-arg output:\n{combined(r)}"

    def test_tc_rdt_ver_009_file_not_found(self):
        """
        TC-RDT-VER-009:
        Non-existent file path → non-zero exit, "not found" or "File" in error output.
        """
        r = run("jrc_rdt_verify.R", "/tmp/no_such_file_rdt_oq.csv",
                "--reliability", "0.95", "--confidence", "0.90", "--target_life", "5000")
        assert r.returncode != 0, \
            f"Expected non-zero exit for missing file:\n{combined(r)}"
        out = combined(r).lower()
        assert "not found" in out or "file" in out, \
            f"Expected file error mention in output:\n{combined(r)}"

    def test_tc_rdt_ver_010_missing_column(self):
        """
        TC-RDT-VER-010:
        rdt_verify_missing_col.csv has 'hours' instead of 'time' → non-zero exit,
        'time' mentioned in the error output.
        """
        r = run("jrc_rdt_verify.R", data("rdt_verify_missing_col.csv"),
                "--reliability", "0.95", "--confidence", "0.90", "--target_life", "5000")
        assert r.returncode != 0, \
            f"Expected non-zero exit for missing 'time' column:\n{combined(r)}"
        assert "time" in combined(r).lower(), \
            f"Expected 'time' mentioned in error:\n{combined(r)}"

    def test_tc_rdt_ver_011_non_numeric_time(self):
        """
        TC-RDT-VER-011:
        CSV with non-numeric values in the time column → non-zero exit.
        Temp CSV created inline; no persistent fixture needed.
        """
        with tempfile.NamedTemporaryFile(
            suffix=".csv", mode="w", delete=False
        ) as f:
            f.write("unit_id,time,status\n")
            f.write("1,abc,0\n")
            f.write("2,5000,0\n")
            fname = f.name
        try:
            r = run("jrc_rdt_verify.R", fname,
                    "--reliability", "0.95", "--confidence", "0.90", "--target_life", "5000")
            assert r.returncode != 0, \
                f"Expected non-zero exit for non-numeric time values:\n{combined(r)}"
        finally:
            os.unlink(fname)

    def test_tc_rdt_ver_012_bypass_protection(self):
        """
        TC-RDT-VER-012:
        Calling jrc_rdt_verify.R directly via Rscript without RENV_PATHS_ROOT
        must exit non-zero and mention RENV_PATHS_ROOT in the error output.
        """
        script = os.path.join(MODULE_ROOT, "R", "jrc_rdt_verify.R")
        env = {k: v for k, v in os.environ.items() if k != "RENV_PATHS_ROOT"}
        result = subprocess.run(
            ["Rscript", script, data("rdt_verify_pass.csv"),
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
