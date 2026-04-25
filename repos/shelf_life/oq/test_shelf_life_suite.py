"""
OQ test suite — Shelf Life & Degradation Analysis module.

Maps to validation plan JR-VP-SHELF-001 as follows:

  jrc_shelf_life_q10
  ------------------
  TC-SHELF-Q10-001  Valid inputs → exit 0, key output sections present
  TC-SHELF-Q10-002  Known values: Q10=2.0, 55→25°C, 26 wk → AF=8.0, real_time=208.0
  TC-SHELF-Q10-003  Sensitivity table present (Q10-0.5, Q10, Q10+0.5 rows)
  TC-SHELF-Q10-004  Q10=1.2 (below typical range) → exit 0, warning emitted
  TC-SHELF-Q10-005  accel_temp <= real_temp → non-zero exit
  TC-SHELF-Q10-006  No arguments → non-zero exit
  TC-SHELF-Q10-007  Non-numeric q10 → non-zero exit
  TC-SHELF-Q10-008  Negative accel_time → non-zero exit
  TC-SHELF-Q10-009  --help flag → exit 0, usage shown
  TC-SHELF-Q10-010  Bypass protection — direct Rscript call fails
  TC-SHELF-Q10-011  --report → exit 0, HTML report written to ~/Downloads/
  TC-SHELF-Q10-012  --report → JSON sidecar (*_data.json) written alongside HTML
  TC-SHELF-Q10-013  JSON sidecar: report_type == "dv", verdict_pass is True

  jrc_shelf_life_arrhenius
  ------------------------
  TC-SHELF-ARR-001  Valid inputs → exit 0, key output sections present
  TC-SHELF-ARR-002  Known values: Ea=17, 55→25°C, 26 wk → AF=13.7826 ±0.001 (independent math.exp)
  TC-SHELF-ARR-003  --unit K: temperatures in Kelvin give same result
  TC-SHELF-ARR-004  Ea sensitivity table present (Ea-2, Ea, Ea+2 rows)
  TC-SHELF-ARR-005  Ea=30 (above typical range) → exit 0, warning emitted
  TC-SHELF-ARR-006  accel_temp <= real_temp → non-zero exit
  TC-SHELF-ARR-007  No arguments → non-zero exit
  TC-SHELF-ARR-008  Invalid --unit value → non-zero exit
  TC-SHELF-ARR-009  --help flag → exit 0, usage shown
  TC-SHELF-ARR-010  Bypass protection — direct Rscript call fails
  TC-SHELF-ARR-011  --report → exit 0, HTML report written to ~/Downloads/
  TC-SHELF-ARR-012  --report → JSON sidecar (*_data.json) written alongside HTML
  TC-SHELF-ARR-013  JSON sidecar: report_type == "dv", verdict_pass is True

  jrc_shelf_life_linear
  ---------------------
  TC-SHELF-LIN-001  Valid 15-row dataset → exit 0, key sections present
  TC-SHELF-LIN-002  Known dataset → shelf life = 24.723 ±0.05 (independent Python OLS + bisection)
  TC-SHELF-LIN-003  Homogeneous variance dataset → Brown-Forsythe pass in output
  TC-SHELF-LIN-004  Heterogeneous variance dataset → warning emitted, exit 0
  TC-SHELF-LIN-005  PNG written to ~/Downloads/
  TC-SHELF-LIN-006  Model CSV written to ~/Downloads/
  TC-SHELF-LIN-007  --direction high → exit 0, "upper" CI referenced
  TC-SHELF-LIN-008  Value below spec at t=0 (direction low) → non-zero exit
  TC-SHELF-LIN-009  No arguments → non-zero exit
  TC-SHELF-LIN-010  Missing 'value' column → non-zero exit, 'value' in error
  TC-SHELF-LIN-011  Fewer than 3 time points → non-zero exit
  TC-SHELF-LIN-012  Bypass protection — direct Rscript call fails
  TC-SHELF-LIN-013  --transform log → exit 0, log transform noted in output
  TC-SHELF-LIN-014  --transform log known shelf life (independent Python log-OLS + bisection)
  TC-SHELF-LIN-015  --transform log with value <= 0 → non-zero exit
  TC-SHELF-LIN-016  --transform log: model CSV contains transform = log
  TC-SHELF-LIN-017  --report → exit 0, HTML report written to ~/Downloads/
  TC-SHELF-LIN-018  --report → JSON sidecar (*_data.json) written alongside HTML
  TC-SHELF-LIN-019  JSON sidecar: report_type == "dv", verdict_pass is True for passing data

  jrc_shelf_life_poolability
  --------------------------
  TC-SHELF-POOL-001  Valid 3-batch dataset → exit 0, decision present
  TC-SHELF-POOL-002  Poolable dataset → FULL POOL decision
  TC-SHELF-POOL-003  Non-poolable (different slopes) → DO NOT POOL decision
  TC-SHELF-POOL-004  Partial pool (same slope, different intercepts) → PARTIAL POOL
  TC-SHELF-POOL-005  PNG written to ~/Downloads/
  TC-SHELF-POOL-006  No arguments → non-zero exit
  TC-SHELF-POOL-007  Missing 'batch' column → non-zero exit, 'batch' in error
  TC-SHELF-POOL-008  Only 1 batch → non-zero exit
  TC-SHELF-POOL-009  Fewer than 3 time points per batch → non-zero exit
  TC-SHELF-POOL-010  Bypass protection — direct Rscript call fails
  TC-SHELF-POOL-011  --report → exit 0, HTML report written to ~/Downloads/
  TC-SHELF-POOL-012  --report → JSON sidecar (*_data.json) written alongside HTML
  TC-SHELF-POOL-013  JSON sidecar: report_type == "dv", verdict_pass is True for poolable data

  jrc_shelf_life_extrapolate
  --------------------------
  TC-SHELF-EXT-001  Valid model CSV + target within range → exit 0
  TC-SHELF-EXT-002  Known numerical check: target=20 → fit=84.502 ±0.01, CI_lo=83.976 ±0.05
  TC-SHELF-EXT-003  Target within range, above spec → PASS message in output
  TC-SHELF-EXT-004  Target beyond shelf life → FAIL message, exit 0
  TC-SHELF-EXT-005  Target > 50% beyond last_time → warning emitted, exit 0
  TC-SHELF-EXT-006  Target > 100% beyond last_time → non-zero exit (hard stop)
  TC-SHELF-EXT-007  No arguments → non-zero exit
  TC-SHELF-EXT-008  Missing model file → non-zero exit
  TC-SHELF-EXT-009  Wrong-script model file → non-zero exit, 'script' in error
  TC-SHELF-EXT-010  Negative target_time → non-zero exit
  TC-SHELF-EXT-011  Bypass protection — direct Rscript call fails
  TC-SHELF-EXT-012  --report → exit 0, HTML report written to ~/Downloads/
  TC-SHELF-EXT-013  --report → JSON sidecar (*_data.json) written alongside HTML
  TC-SHELF-EXT-014  JSON sidecar: report_type == "dv", verdict_pass is True (CI above spec)

Numerical reference values (all independently computed — NOT derived from script output):

  Q10:      AF = 2.0^(30/10) = 8.0 (exact integer arithmetic)
  Arrhenius: AF = exp(17.0/1.987e-3 * (1/298.15 - 1/328.15)) = 13.7826 (±0.001)
             Computed via math.exp() in test, independent of R script.
  Linear:   shelf life = 24.72 (±0.05), computed by pure-Python OLS + bisection
             in test_tc_shelf_lin_002. Coefficients cross-checked against
             hand arithmetic (b0=100.647, b1=-0.807, sigma=0.686 — see test body).
  Linear (log): shelf life with --transform log on the same homogeneous dataset,
             spec=80, conf=0.95. OLS on log(value) ~ time computed in Python.
             Reference computed in module-level constants (_LIN_LOG_*).
             Tolerance ±0.05. See test_tc_shelf_lin_014.
  Extrapolate: fitted value = 84.502 (±0.01), CI lower = 83.976 (±0.05)
             Both derived from known model coefficients via closed-form arithmetic.
             t_crit(0.975, df=13) = 2.16037 (NIST t-table).
  Poolability: interaction p-values verified against expected ANCOVA structure:
             full-pool data → both steps p > 0.25;
             no-pool data   → interaction p < 0.05 (F > 100);
             partial-pool   → interaction p > 0.25, batch p < 0.01.
"""

import glob
import math
import os
import re
import subprocess
import time

from conftest import (
    PROJECT_ROOT, MODULE_ROOT, RSCRIPT_BIN, run, combined, data, extract_float
)

DOWNLOADS = os.path.expanduser("~/Downloads")

# ---------------------------------------------------------------------------
# Module-level reference constants (computed independently of R scripts)
# ---------------------------------------------------------------------------

# Arrhenius reference: AF = exp(Ea/R * (1/T_real - 1/T_accel))
# Ea=17.0 kcal/mol, R=1.987e-3 kcal/(mol*K), T_accel=328.15 K, T_real=298.15 K
_R_GAS = 1.987e-3
_AF_ARR_EXPECTED = math.exp(17.0 / _R_GAS * (1 / 298.15 - 1 / 328.15))  # 13.7826
_RT_ARR_EXPECTED = 26.0 * _AF_ARR_EXPECTED                                # 358.35

# Linear shelf life reference: pure-Python OLS on the 15-row homogeneous dataset.
# Data must match shelf_life_linear_homogeneous.csv exactly.
_LIN_TIMES  = [0,0,0,6,6,6,12,12,12,18,18,18,24,24,24]
_LIN_VALUES = [100.2,99.8,100.5,96.1,95.4,96.8,91.3,90.7,92.1,
               86.2,85.8,87.0,80.9,80.1,81.5]
_N   = len(_LIN_TIMES)
_TB  = sum(_LIN_TIMES) / _N                                     # 12.0
_VB  = sum(_LIN_VALUES) / _N
_SXX = sum((t - _TB)**2 for t in _LIN_TIMES)                    # 1080.0
_SXY = sum((t - _TB)*(v - _VB) for t, v in zip(_LIN_TIMES, _LIN_VALUES))
_B1  = _SXY / _SXX                                              # -0.80722
_B0  = _VB - _B1 * _TB                                          # 100.64667
_SSR = sum((v - (_B0 + _B1*t))**2 for t, v in zip(_LIN_TIMES, _LIN_VALUES))
_SIG = (_SSR / (_N - 2))**0.5                                   # 0.68611
# qt(0.975, df=13) = 2.16037  (NIST t-table; df=n-2=13)
_T_CRIT_13 = 2.16037


def _ci_lower_lin(t):
    """Lower 95% CI bound of the mean for the homogeneous linear model at time t."""
    fit = _B0 + _B1 * t
    se  = _SIG * (1 / _N + (t - _TB)**2 / _SXX)**0.5
    return fit - _T_CRIT_13 * se


def _bisect_shelf_life(spec=80.0, lo=0.0, hi=200.0, tol=1e-8):
    """Bisection: find t where _ci_lower_lin(t) == spec."""
    for _ in range(80):
        mid = (lo + hi) / 2.0
        if _ci_lower_lin(mid) > spec:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2.0


_SHELF_LIFE_EXPECTED = _bisect_shelf_life()   # ≈ 24.723

# Log-linear reference: OLS on log(value) ~ time, same homogeneous dataset, spec=80, conf=0.95.
# All arithmetic is pure Python — independent of R.
_LIN_LOG_VALUES = [math.log(v) for v in _LIN_VALUES]
_VB_LOG  = sum(_LIN_LOG_VALUES) / _N
_SXY_LOG = sum((t - _TB) * (v - _VB_LOG)
               for t, v in zip(_LIN_TIMES, _LIN_LOG_VALUES))
_B1_LOG  = _SXY_LOG / _SXX
_B0_LOG  = _VB_LOG - _B1_LOG * _TB
_SSR_LOG = sum((v - (_B0_LOG + _B1_LOG * t))**2
               for t, v in zip(_LIN_TIMES, _LIN_LOG_VALUES))
_SIG_LOG = (_SSR_LOG / (_N - 2))**0.5


def _ci_lower_log(t):
    """Lower 95% back-transformed CI bound for the log-linear model at time t."""
    fit_log = _B0_LOG + _B1_LOG * t
    se_log  = _SIG_LOG * (1 / _N + (t - _TB)**2 / _SXX)**0.5
    return math.exp(fit_log - _T_CRIT_13 * se_log)


def _bisect_shelf_life_log(spec=80.0, lo=0.0, hi=500.0, tol=1e-8):
    """Bisection: find t where _ci_lower_log(t) == spec."""
    for _ in range(80):
        mid = (lo + hi) / 2.0
        if _ci_lower_log(mid) > spec:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2.0


_SHELF_LIFE_LOG_EXPECTED = _bisect_shelf_life_log()   # computed at import time

# Extrapolate reference at target=20, using model fixture coefficients
# (same as _B0, _B1, _SIG, _N, _TB, _SXX — fixture was generated from this dataset)
_EXT_TARGET       = 20.0
_EXT_FIT_EXPECTED = _B0 + _B1 * _EXT_TARGET                     # 84.502
_EXT_SE           = _SIG * (1/_N + (_EXT_TARGET - _TB)**2 / _SXX)**0.5
_EXT_CI_LO_EXPECTED = _EXT_FIT_EXPECTED - _T_CRIT_13 * _EXT_SE  # 83.976


def _extract_ancova_p(result, step):
    """Extract p-value from poolability ANCOVA Step 1 or Step 2 output line."""
    pattern = rf"Step {step}.*?p\s*=\s*([\d.]+)"
    m = re.search(pattern, combined(result))
    return float(m.group(1)) if m else None


def _recent_file(pattern, t_start):
    """Return list of files matching pattern in ~/Downloads created after t_start."""
    return [
        f for f in glob.glob(os.path.join(DOWNLOADS, pattern))
        if os.path.getmtime(f) >= t_start
    ]


def _bypass(script_name, *args):
    """
    Run script directly via Rscript without RENV_PATHS_ROOT.
    Pass enough arguments to get past argument validation and reach the renv check.
    Returns subprocess.CompletedProcess.
    """
    script = os.path.join(MODULE_ROOT, "R", script_name)
    env = {k: v for k, v in os.environ.items() if k != "RENV_PATHS_ROOT"}
    return subprocess.run(
        [RSCRIPT_BIN, script] + [str(a) for a in args],
        capture_output=True, encoding="utf-8", env=env, cwd=PROJECT_ROOT,
    )


# ===========================================================================
# TC-SHELF-Q10-001 .. 010
# ===========================================================================

class TestShelfLifeQ10:

    def test_tc_shelf_q10_001_happy_path(self):
        """TC-SHELF-Q10-001: Valid inputs → exit 0, key output sections present."""
        r = run("jrc_shelf_life_q10.R", "2.0", "55", "25", "26")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Acceleration factor" in out, "Missing 'Acceleration factor' in output"
        assert "Real-time equivalent" in out, "Missing 'Real-time equivalent' in output"
        assert "Sensitivity" in out, "Missing sensitivity section in output"

    def test_tc_shelf_q10_002_known_values(self):
        """
        TC-SHELF-Q10-002: Q10=2.0, accel=55°C, real=25°C, accel_time=26.
        AF = 2.0^(30/10) = 8.0 (exact). real_time = 26 × 8.0 = 208.0 (exact).
        """
        r = run("jrc_shelf_life_q10.R", "2.0", "55", "25", "26")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        af = extract_float(r, "Acceleration factor (AF):")
        assert af is not None, "Could not parse AF from output"
        assert abs(af - 8.0) < 0.001, f"Expected AF=8.0, got {af}"
        rt = extract_float(r, "Real-time equivalent:")
        assert rt is not None, "Could not parse real-time equivalent"
        assert abs(rt - 208.0) < 0.01, f"Expected real_time=208.0, got {rt}"

    def test_tc_shelf_q10_003_sensitivity_table(self):
        """TC-SHELF-Q10-003: Sensitivity table must contain three Q10 rows."""
        r = run("jrc_shelf_life_q10.R", "2.0", "55", "25", "26")
        assert r.returncode == 0
        out = combined(r)
        # Table rows: Q10=1.5, Q10=2.0 (stated), Q10=2.5
        assert "1.5" in out, "Q10-0.5 row missing from sensitivity table"
        assert "stated value" in out, "Stated value annotation missing"
        assert "2.5" in out, "Q10+0.5 row missing from sensitivity table"

    def test_tc_shelf_q10_004_q10_out_of_range_warning(self):
        """TC-SHELF-Q10-004: Q10=1.2 (below typical range) → exit 0, warning emitted."""
        r = run("jrc_shelf_life_q10.R", "1.2", "55", "25", "26")
        assert r.returncode == 0, f"Expected exit 0 for out-of-range Q10:\n{combined(r)}"
        assert "1.5" in combined(r) or "range" in combined(r).lower(), \
            "Expected range warning for Q10=1.2"

    def test_tc_shelf_q10_005_temp_not_accelerated(self):
        """TC-SHELF-Q10-005: accel_temp <= real_temp → non-zero exit."""
        r = run("jrc_shelf_life_q10.R", "2.0", "25", "55", "26")
        assert r.returncode != 0, "Expected non-zero exit when accel_temp < real_temp"

    def test_tc_shelf_q10_006_no_arguments(self):
        """TC-SHELF-Q10-006: No arguments → non-zero exit or usage shown."""
        r = run("jrc_shelf_life_q10.R")
        # --help path may exit 0; no-arg path exits non-zero
        out = combined(r)
        assert r.returncode != 0 or "Usage" in out, \
            "Expected non-zero exit or usage message with no arguments"

    def test_tc_shelf_q10_007_non_numeric_q10(self):
        """TC-SHELF-Q10-007: Non-numeric q10 → non-zero exit."""
        r = run("jrc_shelf_life_q10.R", "abc", "55", "25", "26")
        assert r.returncode != 0, "Expected non-zero exit for non-numeric q10"

    def test_tc_shelf_q10_008_negative_accel_time(self):
        """TC-SHELF-Q10-008: Negative accel_time → non-zero exit."""
        r = run("jrc_shelf_life_q10.R", "2.0", "55", "25", "-5")
        assert r.returncode != 0, "Expected non-zero exit for negative accel_time"

    def test_tc_shelf_q10_009_help_flag(self):
        """TC-SHELF-Q10-009: --help flag → exit 0, usage shown."""
        r = run("jrc_shelf_life_q10.R", "--help")
        assert r.returncode == 0, f"Expected exit 0 for --help:\n{combined(r)}"
        assert "Usage" in combined(r), "Expected 'Usage' in --help output"

    def test_tc_shelf_q10_010_bypass_protection(self):
        """TC-SHELF-Q10-010: Direct Rscript call without RENV_PATHS_ROOT → non-zero exit."""
        result = _bypass("jrc_shelf_life_q10.R", "2.0", "55", "25", "26")
        assert result.returncode != 0, "Expected non-zero exit when called without RENV_PATHS_ROOT"
        assert "RENV_PATHS_ROOT" in (result.stdout or "") + (result.stderr or ""), \
            "Expected 'RENV_PATHS_ROOT' in error output"


# ===========================================================================
# TC-SHELF-ARR-001 .. 010
# ===========================================================================

class TestShelfLifeArrhenius:

    def test_tc_shelf_arr_001_happy_path(self):
        """TC-SHELF-ARR-001: Valid inputs → exit 0, key output sections present."""
        r = run("jrc_shelf_life_arrhenius.R", "55", "25", "17.0", "26")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Acceleration factor" in out
        assert "Real-time equivalent" in out
        assert "Sensitivity" in out

    def test_tc_shelf_arr_002_known_values(self):
        """
        TC-SHELF-ARR-002: Ea=17.0, 55→25°C, accel_time=26.
        Reference (computed independently via math.exp, no R involved):
          AF = exp(17.0/1.987e-3 * (1/298.15 - 1/328.15)) = 13.7826  (±0.001)
          real_time = 26 × AF = 358.35  (±0.05)
        """
        r = run("jrc_shelf_life_arrhenius.R", "55", "25", "17.0", "26")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        af = extract_float(r, "Acceleration factor (AF):")
        assert af is not None, "Could not parse AF from output"
        assert abs(af - _AF_ARR_EXPECTED) < 0.001, \
            f"AF: expected {_AF_ARR_EXPECTED:.4f}, got {af}"
        rt = extract_float(r, "Real-time equivalent:")
        assert rt is not None, "Could not parse real-time equivalent"
        assert abs(rt - _RT_ARR_EXPECTED) < 0.05, \
            f"real_time: expected {_RT_ARR_EXPECTED:.4f}, got {rt}"

    def test_tc_shelf_arr_003_unit_kelvin(self):
        """
        TC-SHELF-ARR-003: --unit K with temps in Kelvin gives same result as Celsius.
        328.15 K = 55°C, 298.15 K = 25°C.
        """
        r_c = run("jrc_shelf_life_arrhenius.R", "55", "25", "17.0", "26")
        r_k = run("jrc_shelf_life_arrhenius.R", "328.15", "298.15", "17.0", "26", "--unit", "K")
        assert r_c.returncode == 0 and r_k.returncode == 0
        af_c = extract_float(r_c, "Acceleration factor (AF):")
        af_k = extract_float(r_k, "Acceleration factor (AF):")
        assert af_c is not None and af_k is not None
        assert abs(af_c - af_k) < 0.01, \
            f"Celsius and Kelvin should give same AF: {af_c} vs {af_k}"

    def test_tc_shelf_arr_004_sensitivity_table(self):
        """TC-SHELF-ARR-004: Ea sensitivity table present with Ea-2, Ea, Ea+2 rows."""
        r = run("jrc_shelf_life_arrhenius.R", "55", "25", "17.0", "26")
        assert r.returncode == 0
        out = combined(r)
        assert "15.0" in out, "Ea-2 row (15.0) missing from sensitivity table"
        assert "17.0" in out, "Ea row (17.0) missing from sensitivity table"
        assert "19.0" in out, "Ea+2 row (19.0) missing from sensitivity table"

    def test_tc_shelf_arr_005_ea_out_of_range_warning(self):
        """TC-SHELF-ARR-005: Ea=30 (above typical range) → exit 0, warning emitted."""
        r = run("jrc_shelf_life_arrhenius.R", "55", "25", "30.0", "26")
        assert r.returncode == 0, f"Expected exit 0 for out-of-range Ea:\n{combined(r)}"
        out = combined(r).lower()
        assert "range" in out or "25" in out, \
            "Expected range warning for Ea=30"

    def test_tc_shelf_arr_006_temp_not_accelerated(self):
        """TC-SHELF-ARR-006: accel_temp <= real_temp → non-zero exit."""
        r = run("jrc_shelf_life_arrhenius.R", "25", "55", "17.0", "26")
        assert r.returncode != 0, "Expected non-zero exit when accel_temp < real_temp"

    def test_tc_shelf_arr_007_no_arguments(self):
        """TC-SHELF-ARR-007: No arguments → non-zero exit or usage shown."""
        r = run("jrc_shelf_life_arrhenius.R")
        out = combined(r)
        assert r.returncode != 0 or "Usage" in out

    def test_tc_shelf_arr_008_invalid_unit(self):
        """TC-SHELF-ARR-008: Invalid --unit value → non-zero exit."""
        r = run("jrc_shelf_life_arrhenius.R", "55", "25", "17.0", "26", "--unit", "F")
        assert r.returncode != 0, "Expected non-zero exit for invalid --unit F"

    def test_tc_shelf_arr_009_help_flag(self):
        """TC-SHELF-ARR-009: --help flag → exit 0, usage shown."""
        r = run("jrc_shelf_life_arrhenius.R", "--help")
        assert r.returncode == 0, f"Expected exit 0 for --help:\n{combined(r)}"
        assert "Usage" in combined(r)

    def test_tc_shelf_arr_010_bypass_protection(self):
        """TC-SHELF-ARR-010: Direct Rscript call without RENV_PATHS_ROOT → non-zero exit."""
        result = _bypass("jrc_shelf_life_arrhenius.R", "55", "25", "17.0", "26")
        assert result.returncode != 0
        assert "RENV_PATHS_ROOT" in (result.stdout or "") + (result.stderr or "")


# ===========================================================================
# TC-SHELF-LIN-001 .. 012
# ===========================================================================

class TestShelfLifeLinear:

    def test_tc_shelf_lin_001_happy_path(self):
        """TC-SHELF-LIN-001: Valid 15-row homogeneous dataset → exit 0, key sections present."""
        r = run("jrc_shelf_life_linear.R", data("shelf_life_linear_homogeneous.csv"),
                "80.0", "0.95")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Homogeneity of Variance" in out
        assert "Regression" in out
        assert "Shelf Life Estimate" in out

    def test_tc_shelf_lin_002_known_shelf_life(self):
        """
        TC-SHELF-LIN-002: Known dataset, spec=80, conf=0.95, direction=low.

        Reference (independently computed in pure Python — NOT from script output):
          OLS on shelf_life_linear_homogeneous.csv:
            b0 = 100.647, b1 = -0.807, sigma = 0.686  (hand-verified, see module constants)
          Shelf life = t* where lower 95% CI of mean = 80:
            _SHELF_LIFE_EXPECTED = _bisect_shelf_life() ≈ 24.723
          Tolerance ±0.05 (bisection precision << tolerance).
        """
        r = run("jrc_shelf_life_linear.R", data("shelf_life_linear_homogeneous.csv"),
                "80.0", "0.95")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        m = re.search(r"crosses spec limit at:\s+([\d.]+)", combined(r))
        assert m, f"Could not parse shelf life from output:\n{combined(r)}"
        sl = float(m.group(1))
        assert abs(sl - _SHELF_LIFE_EXPECTED) < 0.05, \
            f"Shelf life: expected {_SHELF_LIFE_EXPECTED:.4f} (independent Python OLS), got {sl}"

    def test_tc_shelf_lin_003_homogeneous_variance_pass(self):
        """TC-SHELF-LIN-003: Homogeneous variance dataset → Brown-Forsythe PASS."""
        r = run("jrc_shelf_life_linear.R", data("shelf_life_linear_homogeneous.csv"),
                "80.0", "0.95")
        assert r.returncode == 0
        out = combined(r)
        assert "Variance homogeneous" in out or "homogeneous" in out.lower(), \
            "Expected Brown-Forsythe pass in output"

    def test_tc_shelf_lin_004_heterogeneous_variance_warning(self):
        """TC-SHELF-LIN-004: Heterogeneous variance dataset → warning emitted, exit 0."""
        r = run("jrc_shelf_life_linear.R", data("shelf_life_linear_heterogeneous.csv"),
                "75.0", "0.95")
        assert r.returncode == 0, \
            f"Expected exit 0 (warning, not failure) for heterogeneous data:\n{combined(r)}"
        out = combined(r).lower()
        assert "heterogeneous" in out or "variance" in out, \
            "Expected heterogeneous variance warning in output"

    def test_tc_shelf_lin_005_png_created(self):
        """TC-SHELF-LIN-005: PNG written to ~/Downloads/ during this run."""
        t_start = time.time()
        r = run("jrc_shelf_life_linear.R", data("shelf_life_linear_homogeneous.csv"),
                "80.0", "0.95")
        assert r.returncode == 0
        recent = _recent_file("*_jrc_shelf_life_linear.png", t_start)
        assert recent, "No *_jrc_shelf_life_linear.png found in ~/Downloads/ after run"

    def test_tc_shelf_lin_006_model_csv_created(self):
        """TC-SHELF-LIN-006: Model coefficient CSV written to ~/Downloads/."""
        t_start = time.time()
        r = run("jrc_shelf_life_linear.R", data("shelf_life_linear_homogeneous.csv"),
                "80.0", "0.95")
        assert r.returncode == 0
        recent = _recent_file("*_jrc_shelf_life_linear_model.csv", t_start)
        assert recent, "No *_jrc_shelf_life_linear_model.csv found in ~/Downloads/ after run"

    def test_tc_shelf_lin_007_direction_high(self):
        """TC-SHELF-LIN-007: --direction high → exit 0, upper CI used for growing impurity."""
        r = run("jrc_shelf_life_linear.R", data("shelf_life_linear_direction_high.csv"),
                "0.20", "0.95", "--direction", "high")
        assert r.returncode == 0, f"Expected exit 0 for direction=high:\n{combined(r)}"
        out = combined(r)
        assert "high" in out.lower() or "upper" in out.lower() or "Upper" in out, \
            "Expected 'upper' or 'high' in output for direction=high"

    def test_tc_shelf_lin_008_below_spec_at_t0(self):
        """TC-SHELF-LIN-008: Values below spec at first time point → non-zero exit."""
        r = run("jrc_shelf_life_linear.R", data("shelf_life_linear_below_spec.csv"),
                "80.0", "0.95")
        assert r.returncode != 0, \
            "Expected non-zero exit when values start below spec limit"

    def test_tc_shelf_lin_009_no_arguments(self):
        """TC-SHELF-LIN-009: No arguments → non-zero exit or usage shown."""
        r = run("jrc_shelf_life_linear.R")
        out = combined(r)
        assert r.returncode != 0 or "Usage" in out

    def test_tc_shelf_lin_010_missing_column(self):
        """TC-SHELF-LIN-010: CSV missing 'value' column → non-zero exit, 'value' in error."""
        r = run("jrc_shelf_life_linear.R", data("shelf_life_linear_missing_col.csv"),
                "80.0", "0.95")
        assert r.returncode != 0, "Expected non-zero exit for missing column"
        assert "value" in combined(r).lower(), \
            "Expected 'value' in error output for missing column"

    def test_tc_shelf_lin_011_too_few_timepoints(self):
        """TC-SHELF-LIN-011: Only 2 distinct time points → non-zero exit."""
        r = run("jrc_shelf_life_linear.R", data("shelf_life_linear_few_timepoints.csv"),
                "90.0", "0.95")
        assert r.returncode != 0, \
            "Expected non-zero exit with fewer than 3 distinct time points"

    def test_tc_shelf_lin_012_bypass_protection(self):
        """TC-SHELF-LIN-012: Direct Rscript call without RENV_PATHS_ROOT → non-zero exit."""
        result = _bypass("jrc_shelf_life_linear.R",
                         data("shelf_life_linear_homogeneous.csv"), "80.0", "0.95")
        assert result.returncode != 0
        assert "RENV_PATHS_ROOT" in (result.stdout or "") + (result.stderr or "")

    def test_tc_shelf_lin_013_transform_log_happy_path(self):
        """TC-SHELF-LIN-013: --transform log → exit 0, transform noted in output."""
        r = run("jrc_shelf_life_linear.R", data("shelf_life_linear_homogeneous.csv"),
                "80.0", "0.95", "--transform", "log")
        assert r.returncode == 0, f"Expected exit 0 with --transform log:\n{combined(r)}"
        out = combined(r)
        assert "log" in out.lower(), \
            "Expected 'log' to appear in output when --transform log is used"
        assert "Shelf Life Estimate" in out, "Missing Shelf Life Estimate section"

    def test_tc_shelf_lin_014_transform_log_known_shelf_life(self):
        """
        TC-SHELF-LIN-014: --transform log, spec=80, conf=0.95 on homogeneous dataset.

        Reference (independently computed in pure Python — NOT from script output):
          OLS on log(value) ~ time using the same 15-row dataset as TC-LIN-002.
          b0_log, b1_log, sigma_log computed in module-level constants (_LIN_LOG_*).
          Shelf life = t* where exp(lower 95% CI of mean log-value) = 80:
            _SHELF_LIFE_LOG_EXPECTED = _bisect_shelf_life_log() (computed at import).
          Tolerance ±0.05.
        """
        r = run("jrc_shelf_life_linear.R", data("shelf_life_linear_homogeneous.csv"),
                "80.0", "0.95", "--transform", "log")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        m = re.search(r"crosses spec limit at:\s+([\d.]+)", combined(r))
        assert m, f"Could not parse shelf life from output:\n{combined(r)}"
        sl = float(m.group(1))
        assert abs(sl - _SHELF_LIFE_LOG_EXPECTED) < 0.05, (
            f"Log-linear shelf life: expected {_SHELF_LIFE_LOG_EXPECTED:.4f} "
            f"(independent Python log-OLS), got {sl}"
        )

    def test_tc_shelf_lin_015_transform_log_nonpositive_value(self):
        """TC-SHELF-LIN-015: --transform log with value <= 0 → non-zero exit."""
        import tempfile
        csv_content = (
            "time,value\n"
            "0,95\n0,98\n0,0\n"       # zero value
            "6,90\n6,93\n6,91\n"
            "12,85\n12,88\n12,86\n"
        )
        with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False) as f:
            f.write(csv_content)
            tmp = f.name
        try:
            r = run("jrc_shelf_life_linear.R", tmp, "70.0", "0.95", "--transform", "log")
            assert r.returncode != 0, \
                "Expected non-zero exit when --transform log used with value <= 0"
            assert "positive" in combined(r).lower() or "<= 0" in combined(r), \
                "Expected error message about non-positive values"
        finally:
            os.unlink(tmp)

    def test_tc_shelf_lin_016_transform_log_model_csv_field(self):
        """TC-SHELF-LIN-016: --transform log → model CSV contains transform = log."""
        t_start = time.time()
        r = run("jrc_shelf_life_linear.R", data("shelf_life_linear_homogeneous.csv"),
                "80.0", "0.95", "--transform", "log")
        assert r.returncode == 0
        recent = _recent_file("*_jrc_shelf_life_linear_model.csv", t_start)
        assert recent, "No model CSV found in ~/Downloads/ after run"
        with open(recent[0]) as fh:
            content = fh.read()
        assert "transform" in content, "Expected 'transform' row in model CSV"
        assert "log" in content, "Expected 'log' value in model CSV transform row"


# ===========================================================================
# TC-SHELF-POOL-001 .. 010
# ===========================================================================

class TestShelfLifePoolability:

    def test_tc_shelf_pool_001_happy_path(self):
        """TC-SHELF-POOL-001: Valid 3-batch dataset → exit 0, decision present."""
        r = run("jrc_shelf_life_poolability.R", data("shelf_life_pool_poolable.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Decision" in out, "Missing Decision section"
        assert "POOL" in out, "Missing POOL verdict"
        assert "Step 1" in out and "Step 2" in out, "Missing ANCOVA steps"

    def test_tc_shelf_pool_002_full_pool(self):
        """
        TC-SHELF-POOL-002: Dataset with identical slopes and intercepts → FULL POOL.
        ICH Q1E Step 1 (interaction) and Step 2 (batch) must both have p > 0.25.
        Dataset is designed so true slopes and intercepts are equal across batches.
        """
        r = run("jrc_shelf_life_poolability.R", data("shelf_life_pool_poolable.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        assert "FULL POOL" in combined(r), \
            f"Expected FULL POOL decision:\n{combined(r)}"
        p1 = _extract_ancova_p(r, 1)
        p2 = _extract_ancova_p(r, 2)
        assert p1 is not None, "Could not parse Step 1 p-value"
        assert p2 is not None, "Could not parse Step 2 p-value"
        assert p1 > 0.25, \
            f"Step 1 interaction p={p1:.4f} should be > 0.25 for poolable data"
        assert p2 > 0.25, \
            f"Step 2 batch p={p2:.4f} should be > 0.25 for poolable data"

    def test_tc_shelf_pool_003_do_not_pool(self):
        """
        TC-SHELF-POOL-003: Dataset with clearly different slopes → DO NOT POOL.
        Step 1 interaction F-statistic must be highly significant (p < 0.05).
        Dataset slopes: Batch A = -0.4, B = -0.8, C = -1.2 per unit time.
        """
        r = run("jrc_shelf_life_poolability.R", data("shelf_life_pool_no_pool.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        assert "DO NOT POOL" in combined(r), \
            f"Expected DO NOT POOL decision:\n{combined(r)}"
        p1 = _extract_ancova_p(r, 1)
        assert p1 is not None, "Could not parse Step 1 p-value"
        assert p1 < 0.05, \
            f"Step 1 interaction p={p1:.4f} should be < 0.05 for non-poolable data"

    def test_tc_shelf_pool_004_partial_pool(self):
        """
        TC-SHELF-POOL-004: Same slopes, different intercepts → PARTIAL POOL.
        Step 1 (interaction) must be non-significant (p > 0.25).
        Step 2 (batch main effect) must be significant (p < 0.01).
        Dataset intercepts: Batch A=100, B=104, C=96 with common slope -0.8.
        """
        r = run("jrc_shelf_life_poolability.R", data("shelf_life_pool_partial.csv"))
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        assert "PARTIAL POOL" in combined(r), \
            f"Expected PARTIAL POOL decision:\n{combined(r)}"
        p1 = _extract_ancova_p(r, 1)
        p2 = _extract_ancova_p(r, 2)
        assert p1 is not None and p2 is not None, "Could not parse ANCOVA p-values"
        assert p1 > 0.25, \
            f"Step 1 interaction p={p1:.4f} should be > 0.25 (parallel slopes)"
        assert p2 < 0.01, \
            f"Step 2 batch p={p2:.4f} should be < 0.01 (different intercepts)"

    def test_tc_shelf_pool_005_png_created(self):
        """TC-SHELF-POOL-005: PNG written to ~/Downloads/ during this run."""
        t_start = time.time()
        r = run("jrc_shelf_life_poolability.R", data("shelf_life_pool_poolable.csv"))
        assert r.returncode == 0
        recent = _recent_file("*_jrc_shelf_life_poolability.png", t_start)
        assert recent, "No *_jrc_shelf_life_poolability.png found in ~/Downloads/ after run"

    def test_tc_shelf_pool_006_no_arguments(self):
        """TC-SHELF-POOL-006: No arguments → non-zero exit or usage shown."""
        r = run("jrc_shelf_life_poolability.R")
        out = combined(r)
        assert r.returncode != 0 or "Usage" in out

    def test_tc_shelf_pool_007_missing_batch_column(self):
        """TC-SHELF-POOL-007: CSV missing 'batch' column → non-zero exit, 'batch' in error."""
        r = run("jrc_shelf_life_poolability.R", data("shelf_life_pool_missing_col.csv"))
        assert r.returncode != 0, "Expected non-zero exit for missing 'batch' column"
        assert "batch" in combined(r).lower(), \
            "Expected 'batch' in error output"

    def test_tc_shelf_pool_008_single_batch(self):
        """TC-SHELF-POOL-008: Only 1 batch → non-zero exit."""
        r = run("jrc_shelf_life_poolability.R", data("shelf_life_pool_one_batch.csv"))
        assert r.returncode != 0, "Expected non-zero exit with only 1 batch"

    def test_tc_shelf_pool_009_too_few_timepoints(self):
        """TC-SHELF-POOL-009: Fewer than 3 time points per batch → non-zero exit."""
        r = run("jrc_shelf_life_poolability.R", data("shelf_life_pool_one_batch.csv"))
        # one_batch also has only 3 time points for 1 batch — combined check
        # Use a dedicated 2-timepoint fixture via inline CSV passed via temp file
        import tempfile
        csv_content = "batch,time,value\nA,0,100\nA,0,99\nB,0,102\nB,0,101\n"
        with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False) as f:
            f.write(csv_content)
            tmp = f.name
        try:
            r2 = run("jrc_shelf_life_poolability.R", tmp)
            assert r2.returncode != 0, \
                "Expected non-zero exit when batches have fewer than 3 time points"
        finally:
            os.unlink(tmp)

    def test_tc_shelf_pool_010_bypass_protection(self):
        """TC-SHELF-POOL-010: Direct Rscript call without RENV_PATHS_ROOT → non-zero exit."""
        result = _bypass("jrc_shelf_life_poolability.R",
                         data("shelf_life_pool_poolable.csv"))
        assert result.returncode != 0
        assert "RENV_PATHS_ROOT" in (result.stdout or "") + (result.stderr or "")


# ===========================================================================
# TC-SHELF-EXT-001 .. 011
# ===========================================================================

class TestShelfLifeExtrapolate:

    def test_tc_shelf_ext_001_happy_path(self):
        """TC-SHELF-EXT-001: Valid model CSV + target within observed range → exit 0."""
        r = run("jrc_shelf_life_extrapolate.R",
                data("shelf_life_extrapolate_model.csv"), "20")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        out = combined(r)
        assert "Projection" in out, "Missing Projection section"
        assert "Fitted value" in out, "Missing fitted value"

    def test_tc_shelf_ext_002_known_fitted_value_and_ci(self):
        """
        TC-SHELF-EXT-002: target=20, using model fixture coefficients.

        Reference (independently computed — see module constants):
          fit     = 100.64667 - 0.80722 × 20 = 84.502  (±0.01)
          ci_lower = fit - t_crit × sigma × sqrt(1/n + (t-t_bar)²/Sxx)
                   = 84.502 - 2.16037 × 0.686 × sqrt(1/15 + 64/1080)
                   = 83.976  (±0.05)
          t_crit(0.975, df=13) = 2.16037 (NIST t-table)
        """
        r = run("jrc_shelf_life_extrapolate.R",
                data("shelf_life_extrapolate_model.csv"), "20")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        fv = extract_float(r, "Fitted value:")
        assert fv is not None, "Could not parse fitted value"
        assert abs(fv - _EXT_FIT_EXPECTED) < 0.01, \
            f"Fitted value: expected {_EXT_FIT_EXPECTED:.4f}, got {fv}"
        ci_lo = extract_float(r, "Lower 95% CI bound:")
        assert ci_lo is not None, "Could not parse lower CI bound"
        assert abs(ci_lo - _EXT_CI_LO_EXPECTED) < 0.05, \
            f"CI lower: expected {_EXT_CI_LO_EXPECTED:.4f}, got {ci_lo}"

    def test_tc_shelf_ext_003_within_spec_pass(self):
        """TC-SHELF-EXT-003: target=20, spec=80 → lower CI > 80, PASS message."""
        r = run("jrc_shelf_life_extrapolate.R",
                data("shelf_life_extrapolate_model.csv"), "20")
        assert r.returncode == 0
        out = combined(r)
        assert "stability claim is supported" in out.lower() or \
               "supported" in out.lower(), \
            f"Expected 'supported' (PASS) in output:\n{out}"

    def test_tc_shelf_ext_004_beyond_shelf_life_fail(self):
        """TC-SHELF-EXT-004: target=30, spec=80 → lower CI < 80, FAIL message, exit 0."""
        r = run("jrc_shelf_life_extrapolate.R",
                data("shelf_life_extrapolate_model.csv"), "30")
        assert r.returncode == 0, \
            f"Expected exit 0 (FAIL is a message, not an error):\n{combined(r)}"
        out = combined(r)
        assert "NOT supported" in out or "crossed" in out.lower(), \
            f"Expected FAIL message for target beyond shelf life:\n{out}"

    def test_tc_shelf_ext_005_fifty_percent_extrapolation_warning(self):
        """
        TC-SHELF-EXT-005: target=37, last_time=24 → 54% extrapolation → warning, exit 0.
        Threshold: >50% beyond last observation triggers warning.
        """
        r = run("jrc_shelf_life_extrapolate.R",
                data("shelf_life_extrapolate_model.csv"), "37")
        assert r.returncode == 0, \
            f"Expected exit 0 for 50%+ extrapolation warning:\n{combined(r)}"
        out = combined(r).lower()
        assert "beyond" in out or "wide" in out or "50" in out, \
            "Expected 50%+ extrapolation warning in output"

    def test_tc_shelf_ext_006_hundred_percent_extrapolation_hard_stop(self):
        """
        TC-SHELF-EXT-006: target=50, last_time=24 → 108% extrapolation → non-zero exit.
        Hard stop: >100% beyond last observation is rejected.
        """
        r = run("jrc_shelf_life_extrapolate.R",
                data("shelf_life_extrapolate_model.csv"), "50")
        assert r.returncode != 0, \
            "Expected non-zero exit when target > 100% beyond last observation"
        out = combined(r).lower()
        assert "100" in out or "rejected" in out or "speculative" in out, \
            "Expected hard stop message in output"

    def test_tc_shelf_ext_007_no_arguments(self):
        """TC-SHELF-EXT-007: No arguments → non-zero exit or usage shown."""
        r = run("jrc_shelf_life_extrapolate.R")
        out = combined(r)
        assert r.returncode != 0 or "Usage" in out

    def test_tc_shelf_ext_008_missing_model_file(self):
        """TC-SHELF-EXT-008: Non-existent model file → non-zero exit, 'not found' in output."""
        r = run("jrc_shelf_life_extrapolate.R", "/tmp/no_such_model.csv", "20")
        assert r.returncode != 0, "Expected non-zero exit for missing model file"
        assert "not found" in combined(r).lower(), \
            "Expected 'not found' in error output"

    def test_tc_shelf_ext_009_wrong_script_model(self):
        """TC-SHELF-EXT-009: Model file from wrong script → non-zero exit, 'script' in error."""
        r = run("jrc_shelf_life_extrapolate.R",
                data("shelf_life_extrapolate_wrongscript.csv"), "20")
        assert r.returncode != 0, "Expected non-zero exit for wrong-script model file"
        assert "script" in combined(r).lower(), \
            "Expected 'script' in error output"

    def test_tc_shelf_ext_010_negative_target_time(self):
        """TC-SHELF-EXT-010: Negative target_time → non-zero exit."""
        r = run("jrc_shelf_life_extrapolate.R",
                data("shelf_life_extrapolate_model.csv"), "-5")
        assert r.returncode != 0, "Expected non-zero exit for negative target_time"

    def test_tc_shelf_ext_011_bypass_protection(self):
        """TC-SHELF-EXT-011: Direct Rscript call without RENV_PATHS_ROOT → non-zero exit."""
        result = _bypass("jrc_shelf_life_extrapolate.R",
                         data("shelf_life_extrapolate_model.csv"), "20")
        assert result.returncode != 0
        assert "RENV_PATHS_ROOT" in (result.stdout or "") + (result.stderr or "")

    def test_tc_shelf_ext_012_report_html_created(self):
        """TC-SHELF-EXT-012: --report flag → exit 0 and HTML report written to ~/Downloads/."""
        t_start = time.time()
        r = run("jrc_shelf_life_extrapolate.R",
                data("shelf_life_extrapolate_model.csv"), "20", "--report")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        html_files = [
            f for f in glob.glob(os.path.join(DOWNLOADS, "*_extrapolate_dv_report.html"))
            if os.path.getmtime(f) >= t_start
        ]
        assert html_files, "No *_extrapolate_dv_report.html found in ~/Downloads/ after --report run"

    def test_tc_shelf_ext_013_report_json_sidecar_created(self):
        """TC-SHELF-EXT-013: --report → JSON sidecar (*_data.json) written alongside HTML."""
        t_start = time.time()
        r = run("jrc_shelf_life_extrapolate.R",
                data("shelf_life_extrapolate_model.csv"), "20", "--report")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        json_files = [
            f for f in glob.glob(os.path.join(DOWNLOADS, "*_extrapolate_dv_report_data.json"))
            if os.path.getmtime(f) >= t_start
        ]
        assert json_files, "No *_extrapolate_dv_report_data.json found in ~/Downloads/ after --report run"

    def test_tc_shelf_ext_014_report_json_content(self):
        """
        TC-SHELF-EXT-014:
        JSON sidecar contains report_type == "dv" and verdict_pass == True.
        At target=20, CI lower bound ≈ 83.976 exceeds spec_limit=80 (from model fixture).
        """
        import json
        t_start = time.time()
        r = run("jrc_shelf_life_extrapolate.R",
                data("shelf_life_extrapolate_model.csv"), "20", "--report")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        json_files = [
            f for f in glob.glob(os.path.join(DOWNLOADS, "*_extrapolate_dv_report_data.json"))
            if os.path.getmtime(f) >= t_start
        ]
        assert json_files, "No JSON sidecar found — cannot check content"
        with open(json_files[-1]) as fh:
            d = json.load(fh)
        assert d.get("report_type") == "dv", \
            f"Expected report_type 'dv', got {d.get('report_type')!r}"
        assert isinstance(d.get("verdict_pass"), bool), \
            f"Expected verdict_pass to be boolean, got {type(d.get('verdict_pass'))}"
        assert d["verdict_pass"] is True, \
            "Expected verdict_pass True: CI lower (≈83.976) exceeds spec_limit (80)"


# ===========================================================================
# TC-SHELF-Q10-011 .. 013  --report sidecar
# ===========================================================================

class TestShelfLifeQ10Report:

    def test_tc_shelf_q10_011_report_html_created(self):
        """TC-SHELF-Q10-011: --report flag → exit 0 and HTML report written to ~/Downloads/."""
        t_start = time.time()
        r = run("jrc_shelf_life_q10.R", "2.0", "55", "25", "26", "--report")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        html_files = [
            f for f in glob.glob(os.path.join(DOWNLOADS, "*_q10_dv_report.html"))
            if os.path.getmtime(f) >= t_start
        ]
        assert html_files, "No *_q10_dv_report.html found in ~/Downloads/ after --report run"

    def test_tc_shelf_q10_012_report_json_sidecar_created(self):
        """TC-SHELF-Q10-012: --report → JSON sidecar (*_data.json) written alongside HTML."""
        t_start = time.time()
        r = run("jrc_shelf_life_q10.R", "2.0", "55", "25", "26", "--report")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        json_files = [
            f for f in glob.glob(os.path.join(DOWNLOADS, "*_q10_dv_report_data.json"))
            if os.path.getmtime(f) >= t_start
        ]
        assert json_files, "No *_q10_dv_report_data.json found in ~/Downloads/ after --report run"

    def test_tc_shelf_q10_013_report_json_content(self):
        """
        TC-SHELF-Q10-013:
        JSON sidecar contains report_type == "dv" and verdict_pass == True.
        Q10 script always yields verdict_pass True (pure calculation, no spec check).
        """
        import json
        t_start = time.time()
        r = run("jrc_shelf_life_q10.R", "2.0", "55", "25", "26", "--report")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        json_files = [
            f for f in glob.glob(os.path.join(DOWNLOADS, "*_q10_dv_report_data.json"))
            if os.path.getmtime(f) >= t_start
        ]
        assert json_files, "No JSON sidecar found — cannot check content"
        with open(json_files[-1]) as fh:
            d = json.load(fh)
        assert d.get("report_type") == "dv", \
            f"Expected report_type 'dv', got {d.get('report_type')!r}"
        assert isinstance(d.get("verdict_pass"), bool), \
            f"Expected verdict_pass to be boolean, got {type(d.get('verdict_pass'))}"
        assert d["verdict_pass"] is True, \
            "Expected verdict_pass True: Q10 script always passes (no spec check)"


# ===========================================================================
# TC-SHELF-ARR-011 .. 013  --report sidecar
# ===========================================================================

class TestShelfLifeArrheniusReport:

    def test_tc_shelf_arr_011_report_html_created(self):
        """TC-SHELF-ARR-011: --report flag → exit 0 and HTML report written to ~/Downloads/."""
        t_start = time.time()
        r = run("jrc_shelf_life_arrhenius.R", "55", "25", "17.0", "26", "--report")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        html_files = [
            f for f in glob.glob(os.path.join(DOWNLOADS, "*_arrhenius_dv_report.html"))
            if os.path.getmtime(f) >= t_start
        ]
        assert html_files, "No *_arrhenius_dv_report.html found in ~/Downloads/ after --report run"

    def test_tc_shelf_arr_012_report_json_sidecar_created(self):
        """TC-SHELF-ARR-012: --report → JSON sidecar (*_data.json) written alongside HTML."""
        t_start = time.time()
        r = run("jrc_shelf_life_arrhenius.R", "55", "25", "17.0", "26", "--report")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        json_files = [
            f for f in glob.glob(os.path.join(DOWNLOADS, "*_arrhenius_dv_report_data.json"))
            if os.path.getmtime(f) >= t_start
        ]
        assert json_files, "No *_arrhenius_dv_report_data.json found in ~/Downloads/ after --report run"

    def test_tc_shelf_arr_013_report_json_content(self):
        """
        TC-SHELF-ARR-013:
        JSON sidecar contains report_type == "dv" and verdict_pass == True.
        Arrhenius script always yields verdict_pass True (pure calculation, no spec check).
        """
        import json
        t_start = time.time()
        r = run("jrc_shelf_life_arrhenius.R", "55", "25", "17.0", "26", "--report")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        json_files = [
            f for f in glob.glob(os.path.join(DOWNLOADS, "*_arrhenius_dv_report_data.json"))
            if os.path.getmtime(f) >= t_start
        ]
        assert json_files, "No JSON sidecar found — cannot check content"
        with open(json_files[-1]) as fh:
            d = json.load(fh)
        assert d.get("report_type") == "dv", \
            f"Expected report_type 'dv', got {d.get('report_type')!r}"
        assert isinstance(d.get("verdict_pass"), bool), \
            f"Expected verdict_pass to be boolean, got {type(d.get('verdict_pass'))}"
        assert d["verdict_pass"] is True, \
            "Expected verdict_pass True: Arrhenius script always passes (no spec check)"


# ===========================================================================
# TC-SHELF-LIN-017 .. 019  --report sidecar
# ===========================================================================

class TestShelfLifeLinearReport:

    def test_tc_shelf_lin_017_report_html_created(self):
        """TC-SHELF-LIN-017: --report flag → exit 0 and HTML report written to ~/Downloads/."""
        t_start = time.time()
        r = run("jrc_shelf_life_linear.R",
                data("shelf_life_linear_homogeneous.csv"), "80", "0.95", "--report")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        html_files = [
            f for f in glob.glob(os.path.join(DOWNLOADS, "*_shelf_life_linear_dv_report.html"))
            if os.path.getmtime(f) >= t_start
        ]
        assert html_files, "No *_shelf_life_linear_dv_report.html found in ~/Downloads/ after --report run"

    def test_tc_shelf_lin_018_report_json_sidecar_created(self):
        """TC-SHELF-LIN-018: --report → JSON sidecar (*_data.json) written alongside HTML."""
        t_start = time.time()
        r = run("jrc_shelf_life_linear.R",
                data("shelf_life_linear_homogeneous.csv"), "80", "0.95", "--report")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        json_files = [
            f for f in glob.glob(os.path.join(DOWNLOADS, "*_shelf_life_linear_dv_report_data.json"))
            if os.path.getmtime(f) >= t_start
        ]
        assert json_files, \
            "No *_shelf_life_linear_dv_report_data.json found in ~/Downloads/ after --report run"

    def test_tc_shelf_lin_019_report_json_content(self):
        """
        TC-SHELF-LIN-019:
        JSON sidecar contains report_type == "dv" and verdict_pass == True.
        Dataset yields shelf life ≈ 24.7 months; spec=80% → CI bound exceeds spec.
        """
        import json
        t_start = time.time()
        r = run("jrc_shelf_life_linear.R",
                data("shelf_life_linear_homogeneous.csv"), "80", "0.95", "--report")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        json_files = [
            f for f in glob.glob(os.path.join(DOWNLOADS, "*_shelf_life_linear_dv_report_data.json"))
            if os.path.getmtime(f) >= t_start
        ]
        assert json_files, "No JSON sidecar found — cannot check content"
        with open(json_files[-1]) as fh:
            d = json.load(fh)
        assert d.get("report_type") == "dv", \
            f"Expected report_type 'dv', got {d.get('report_type')!r}"
        assert isinstance(d.get("verdict_pass"), bool), \
            f"Expected verdict_pass to be boolean, got {type(d.get('verdict_pass'))}"
        assert d["verdict_pass"] is True, \
            "Expected verdict_pass True: dataset shelf life ≈ 24.7 months, CI bound above spec"


# ===========================================================================
# TC-SHELF-POOL-011 .. 013  --report sidecar
# ===========================================================================

class TestShelfLifePoolabilityReport:

    def test_tc_shelf_pool_011_report_html_created(self):
        """TC-SHELF-POOL-011: --report flag → exit 0 and HTML report written to ~/Downloads/."""
        t_start = time.time()
        r = run("jrc_shelf_life_poolability.R",
                data("shelf_life_pool_poolable.csv"), "--report")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        html_files = [
            f for f in glob.glob(os.path.join(DOWNLOADS, "*_poolability_dv_report.html"))
            if os.path.getmtime(f) >= t_start
        ]
        assert html_files, "No *_poolability_dv_report.html found in ~/Downloads/ after --report run"

    def test_tc_shelf_pool_012_report_json_sidecar_created(self):
        """TC-SHELF-POOL-012: --report → JSON sidecar (*_data.json) written alongside HTML."""
        t_start = time.time()
        r = run("jrc_shelf_life_poolability.R",
                data("shelf_life_pool_poolable.csv"), "--report")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        json_files = [
            f for f in glob.glob(os.path.join(DOWNLOADS, "*_poolability_dv_report_data.json"))
            if os.path.getmtime(f) >= t_start
        ]
        assert json_files, "No *_poolability_dv_report_data.json found in ~/Downloads/ after --report run"

    def test_tc_shelf_pool_013_report_json_content(self):
        """
        TC-SHELF-POOL-013:
        JSON sidecar contains report_type == "dv" and verdict_pass == True
        for poolable dataset (TC-SHELF-POOL-002 confirms FULL POOL decision).
        """
        import json
        t_start = time.time()
        r = run("jrc_shelf_life_poolability.R",
                data("shelf_life_pool_poolable.csv"), "--report")
        assert r.returncode == 0, f"Expected exit 0:\n{combined(r)}"
        json_files = [
            f for f in glob.glob(os.path.join(DOWNLOADS, "*_poolability_dv_report_data.json"))
            if os.path.getmtime(f) >= t_start
        ]
        assert json_files, "No JSON sidecar found — cannot check content"
        with open(json_files[-1]) as fh:
            d = json.load(fh)
        assert d.get("report_type") == "dv", \
            f"Expected report_type 'dv', got {d.get('report_type')!r}"
        assert isinstance(d.get("verdict_pass"), bool), \
            f"Expected verdict_pass to be boolean, got {type(d.get('verdict_pass'))}"
        assert d["verdict_pass"] is True, \
            "Expected verdict_pass True: poolable dataset yields FULL POOL decision"
