"""
SPC module OQ test suite — shared configuration and helpers.

All SPC test modules import helpers from this file.
"""

import os
import subprocess

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

OQ_DIR       = os.path.dirname(os.path.abspath(__file__))
MODULE_ROOT  = os.path.dirname(OQ_DIR)                        # repos/spc/
PROJECT_ROOT = os.path.dirname(os.path.dirname(MODULE_ROOT))  # project root
JRRUN        = os.path.join(PROJECT_ROOT, "bin", "jrrun")
DATA_DIR     = os.path.join(OQ_DIR, "data")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def run(script, *args, cwd=None):
    """
    Invoke a script via jrrun and return subprocess.CompletedProcess.
    stdout and stderr are both captured as text.
    """
    cmd = [JRRUN, script] + [str(a) for a in args]
    return subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        cwd=cwd or DATA_DIR,
    )


def combined(result):
    """Return stdout + stderr as a single string for pattern matching."""
    return result.stdout + result.stderr


def data(name):
    """Return full path to a file in the OQ data directory."""
    return os.path.join(DATA_DIR, name)
