"""
Clinical module OQ test suite — shared configuration and helpers.

All clinical test modules import helpers from this file.

Two kinds of script live in this module:

  * The sample-size scripts (ss_means, ss_props, ss_survival, dx_ss) are
    parameter-only. Every test drives the script through jrrun with
    command-line flags and asserts on the report text and exit code.

  * The analysis scripts (dx_accuracy, dx_roc) consume a CSV. Their fixtures
    live in repos/clinical/oq/data/ and are resolved with data(); jrrun does
    not preserve the caller's working directory, so fixture paths must be
    absolute.
"""

import os
import re
import subprocess
import sys

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

OQ_DIR       = os.path.dirname(os.path.abspath(__file__))
MODULE_ROOT  = os.path.dirname(OQ_DIR)                        # repos/clinical/
PROJECT_ROOT = os.path.dirname(os.path.dirname(MODULE_ROOT))  # project root
JRRUN        = os.path.join(PROJECT_ROOT, "bin", "jrrun")
DATA_DIR     = os.path.join(OQ_DIR, "data")


def data(name):
    """
    Absolute path to an OQ fixture in repos/clinical/oq/data/.

    Always absolute: jrrun does not run the script in the caller's working
    directory, so a relative fixture path would not resolve. Fails loudly
    rather than letting a test assert against a "file not found" error and
    appear to pass for the wrong reason.
    """
    p = os.path.join(DATA_DIR, name)
    if not os.path.exists(p):
        raise FileNotFoundError(f"OQ fixture missing: {p}")
    return p


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

BASH_PREFIX = ["bash"] if sys.platform == "win32" else []

if sys.platform == "win32":
    import glob as _glob
    _candidates = sorted(_glob.glob(r"C:\Program Files\R\R-*\bin\Rscript.exe"))
    RSCRIPT_BIN = _candidates[-1] if _candidates else "Rscript"
else:
    RSCRIPT_BIN = "Rscript"


def run(script, *args, cwd=None):
    """
    Invoke a script via jrrun and return subprocess.CompletedProcess.
    stdout and stderr are both captured as text.
    """
    cmd = BASH_PREFIX + [JRRUN, script] + [str(a) for a in args]
    result = subprocess.run(
        cmd,
        capture_output=True,
        encoding="utf-8",
        stdin=subprocess.DEVNULL,
        cwd=cwd or OQ_DIR,
    )
    # Print invocation and output for OQ evidence (visible with pytest -s)
    args_str = " ".join(str(a) for a in args)
    print(f"\n  CMD : {script} {args_str}")
    out = (result.stdout or "") + (result.stderr or "")
    for line in out.rstrip().splitlines():
        print(f"  OUT : {line}")
    print(f"  EXIT: {result.returncode}")
    return result


def combined(result):
    """Return stdout + stderr as a single string for pattern matching."""
    return (result.stdout or "") + (result.stderr or "")


def report_int(result, label):
    """
    Extract the integer that follows 'label ... :' in a report line, e.g.
    report_int(r, "n TOTAL") reads '   n TOTAL        : 126  (...)' -> 126.
    Returns int, or None if the line is not found.
    """
    m = re.search(rf"{re.escape(label)}\s*:\s*(-?\d+)", combined(result))
    return int(m.group(1)) if m else None


def report_float(result, label):
    """
    Extract the float that follows 'label ... :' in a report line, e.g.
    report_float(r, "AUC") reads '   AUC            : 0.8268' -> 0.8268.
    Returns float, or None if the line is not found.
    """
    m = re.search(rf"{re.escape(label)}\s*:\s*(-?\d+\.\d+)", combined(result))
    return float(m.group(1)) if m else None


def report_est_ci(result, label):
    """
    Parse an estimate-with-interval report line, e.g.
      '   Sensitivity    : 0.8316  (0.7410, 0.9006)   [79/95]'
    -> (0.8316, 0.7410, 0.9006). Returns None if the line is not found or
    the interval is not estimable (printed as n/a).
    """
    m = re.search(
        rf"{re.escape(label)}\s*:\s*(-?\d+\.\d+)\s*\(\s*(-?\d+\.\d+),\s*"
        rf"(-?\d+\.\d+)\s*\)",
        combined(result),
    )
    if not m:
        return None
    return float(m.group(1)), float(m.group(2)), float(m.group(3))


def run_direct_rscript(script_relpath, *args):
    """
    Invoke the R script DIRECTLY via Rscript, bypassing jrrun, with
    RENV_PATHS_ROOT removed from the environment — for the bypass-guardrail
    test. Returns subprocess.CompletedProcess.
    """
    env = {k: v for k, v in os.environ.items() if k != "RENV_PATHS_ROOT"}
    script_path = os.path.join(PROJECT_ROOT, script_relpath)
    result = subprocess.run(
        [RSCRIPT_BIN, "--vanilla", script_path] + [str(a) for a in args],
        capture_output=True,
        encoding="utf-8",
        stdin=subprocess.DEVNULL,
        env=env,
        cwd=OQ_DIR,
    )
    print(f"\n  CMD : Rscript --vanilla {script_relpath} (no RENV_PATHS_ROOT)")
    out = (result.stdout or "") + (result.stderr or "")
    for line in out.rstrip().splitlines():
        print(f"  OUT : {line}")
    print(f"  EXIT: {result.returncode}")
    return result
