"""
Clinical module OQ test suite — shared configuration and helpers.

All clinical test modules import helpers from this file. The clinical
sample-size scripts are parameter-only (no data files): every test drives
the script through jrrun with command-line flags and asserts on the
report text and exit code.
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
