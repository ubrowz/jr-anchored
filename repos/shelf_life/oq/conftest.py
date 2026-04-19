"""
Shelf life module OQ test suite — shared configuration and helpers.

All shelf life test modules import helpers from this file.
"""

import os
import re
import subprocess
import sys

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

OQ_DIR      = os.path.dirname(os.path.abspath(__file__))
MODULE_ROOT = os.path.dirname(OQ_DIR)                        # repos/shelf_life/
PROJECT_ROOT = os.path.dirname(os.path.dirname(MODULE_ROOT)) # project root
JRRUN       = os.path.join(PROJECT_ROOT, "bin", "jrrun")
DATA_DIR    = os.path.join(OQ_DIR, "data")

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
    """Invoke a script via jrrun and return subprocess.CompletedProcess."""
    cmd = BASH_PREFIX + [JRRUN, script] + [str(a) for a in args]
    result = subprocess.run(
        cmd,
        capture_output=True,
        encoding="utf-8",
        cwd=cwd or DATA_DIR,
    )
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


def data(name):
    """Return full path to a file in the OQ data directory."""
    return os.path.join(DATA_DIR, name)


def extract_float(result, label):
    """
    Extract the first float that follows *label* in the combined output.
    Returns float, or None if not found.
    """
    m = re.search(rf"{re.escape(label)}\s+([-\d.]+)", combined(result))
    return float(m.group(1)) if m else None
