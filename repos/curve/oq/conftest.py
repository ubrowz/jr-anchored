"""
Curve module OQ test suite — shared configuration and helpers.

All curve test modules import helpers from this file.
"""

import os
import subprocess
import sys

# Paths
OQ_DIR       = os.path.dirname(os.path.abspath(__file__))      # repos/curve/oq/
MODULE_ROOT  = os.path.dirname(OQ_DIR)                         # repos/curve/
PROJECT_ROOT = os.path.dirname(os.path.dirname(MODULE_ROOT))   # project root
JRRUN        = os.path.join(PROJECT_ROOT, "bin", "jrrun")
DATA_DIR     = os.path.join(OQ_DIR, "data")

BASH_PREFIX = ["bash"] if sys.platform == "win32" else []


def run(script, *args, cwd=None):
    """
    Invoke a script via jrrun and return subprocess.CompletedProcess.
    stdout and stderr are both captured as text.

    Example: run("jrc_curve_properties.py", data("test_global.cfg"))
    """
    cmd = BASH_PREFIX + [JRRUN, script] + [str(a) for a in args]
    return subprocess.run(
        cmd,
        capture_output=True,
        encoding="utf-8",
        cwd=cwd or DATA_DIR,
    )


def combined(result):
    """Return stdout + stderr as a single string for pattern matching."""
    return (result.stdout or "") + (result.stderr or "")


def data(name):
    """Return full path to a file in the OQ data directory."""
    return os.path.join(DATA_DIR, name)
