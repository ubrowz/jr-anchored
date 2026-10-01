"""
OQ/IQ test suite — Core environment infrastructure.

Maps to validation plan JR-VP-001 as follows:

  TC-CORE-IQ-001  admin_validate passes and writes evidence file      (IQ-3 / OQ-05)
  TC-CORE-OQ-001  jrc_R_hello.R executes successfully via jrrun       (OQ-03 / PQ-01)
  TC-CORE-OQ-002  jrc_py_hello.py executes successfully via jrrun     (OQ-04 / PQ-02)
  TC-CORE-OQ-003  Integrity check detects a tampered tracked file      (OQ-09)
  TC-CORE-OQ-004  Bypass protection — R direct invocation fails        (OQ-10)
  TC-CORE-OQ-005  Bypass protection — Python direct invocation fails   (OQ-10)

Not automated (remain manual per JR-VP-001):
  OQ-01  R environment rebuild from scratch   — deletes ~/.renv/<PROJECT_ID>
  OQ-02  Python environment rebuild from scratch — deletes ~/.venvs/<PROJECT_ID>
  OQ-06  Auto-rebuild triggered by missing renv hash
  OQ-07  admin_install_R --add <package>
  OQ-08  admin_install_Python --add <package>
"""

import glob
import os
import subprocess
import sys
import time

from conftest import (DATA_DIR, JRRUN, PROJECT_ROOT, BASH_PREFIX,
                      PYTHON_BIN, VENV_BIN_DIR, PATH_SEP, RSCRIPT_BIN,
                      combined, run)


# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------

def _project_id():
    """Read PROJECT_ID from admin/project_id.txt."""
    path = os.path.join(PROJECT_ROOT, "admin", "project_id.txt")
    with open(path) as fh:
        return fh.read().strip()


# ===========================================================================
# IQ — Installation Qualification
# ===========================================================================

class TestCoreIQ:

    def test_tc_core_iq_001_admin_validate_passes(self):
        """
        TC-CORE-IQ-001 (IQ-3 / OQ-05):
        admin_validate exits 0, reports PASSED, and writes a timestamped
        evidence file to ~/.jrscript/<PROJECT_ID>/validation/.
        """
        t_start = time.time()
        result = subprocess.run(
            BASH_PREFIX + [os.path.join(PROJECT_ROOT, "admin", "admin_validate")],
            capture_output=True,
            encoding="utf-8",
            cwd=PROJECT_ROOT,
        )
        out = (result.stdout or "") + (result.stderr or "")
        assert result.returncode == 0, f"admin_validate failed:\n{out}"
        assert "PASSED" in out, \
            f"'PASSED' not found in admin_validate output:\n{out}"

        project_id = _project_id()
        evidence_dir = os.path.expanduser(f"~/.jrscript/{project_id}/validation")
        all_files = glob.glob(os.path.join(evidence_dir, "validation_*.txt"))
        recent = [f for f in all_files if os.path.getmtime(f) >= t_start]
        assert recent, (
            f"No evidence file written to {evidence_dir} during this run.\n"
            f"Existing files: {all_files}"
        )


# ===========================================================================
# OQ — Operational Qualification
# ===========================================================================

class TestCoreOQ:

    def test_tc_core_oq_001_r_hello_runs(self):
        """
        TC-CORE-OQ-001 (OQ-03 / PQ-01):
        jrc_R_hello.R executes via jrrun in the validated R environment,
        exits 0, and prints the supplied message and a Done confirmation.
        """
        r = run("jrc_R_hello.R", "Validation")
        assert r.returncode == 0, f"jrc_R_hello.R failed:\n{combined(r)}"
        assert "Validation" in combined(r)
        assert "Done" in combined(r)

    def test_tc_core_oq_002_python_hello_runs(self):
        """
        TC-CORE-OQ-002 (OQ-04 / PQ-02):
        jrc_py_hello.py executes via jrrun in the validated Python environment
        and prints the supplied message.

        The script opens an interactive matplotlib window on a machine with a
        display and will block until the window is closed. A 15-second timeout
        is used: if the process is still running after 15 s, that means it
        launched successfully and is displaying the window — this is treated
        as a pass provided the expected output was already printed.
        """
        # Windows with Defender needs more time for venv setup on first run.
        _timeout = 60 if sys.platform == "win32" else 15
        try:
            result = subprocess.run(
                BASH_PREFIX + [JRRUN, "jrc_py_hello.py", "Validation"],
                capture_output=True,
                encoding="utf-8",
                timeout=_timeout,
                cwd=DATA_DIR,
            )
            out = (result.stdout or "") + (result.stderr or "")
            assert result.returncode == 0, f"jrc_py_hello.py failed:\n{out}"
            assert "Validation" in out
        except subprocess.TimeoutExpired as exc:
            # Still running after timeout — GUI window is open. Check partial output.
            # exc.stdout/stderr may be str or bytes depending on Python version/platform.
            def _to_str(v):
                if isinstance(v, bytes):
                    return v.decode("utf-8", errors="replace")
                return v or ""
            partial = _to_str(exc.stdout) + _to_str(exc.stderr)
            assert "Validation" in partial, (
                f"Script timed out without printing the expected message.\n"
                f"Partial output:\n{partial}"
            )

    def test_tc_core_oq_003_integrity_check_detects_tamper(self):
        """
        TC-CORE-OQ-003 (OQ-09):
        jrrun detects that a tracked file has been tampered with, exits
        non-zero, and emits an integrity failure message.

        One byte is appended to bin/jrrun (changing its SHA256) and restored
        unconditionally in the finally block regardless of test outcome.
        """
        target = os.path.join(PROJECT_ROOT, "bin", "jrrun")
        with open(target, "rb") as fh:
            original = fh.read()
        try:
            with open(target, "ab") as fh:
                fh.write(b"\n")  # one extra byte changes the SHA256
            r = run("jrc_R_hello.R", "Validation")
            out = combined(r)
            assert r.returncode != 0, \
                "Expected non-zero exit when a tracked file is tampered"
            assert any(kw in out.upper() for kw in ("INTEGRITY", "FAILED", "CHECK")), \
                f"Expected integrity failure message in output:\n{out}"
        finally:
            with open(target, "wb") as fh:
                fh.write(original)

    def test_tc_core_oq_004_r_bypass_protection(self):
        """
        TC-CORE-OQ-004 (OQ-10):
        Calling an R script directly via Rscript without RENV_PATHS_ROOT set
        exits non-zero. The script explicitly stops with a message referencing
        RENV_PATHS_ROOT so the failure is unambiguous.
        """
        script = os.path.join(PROJECT_ROOT, "R", "jrc_R_hello.R")
        env = {k: v for k, v in os.environ.items() if k != "RENV_PATHS_ROOT"}
        result = subprocess.run(
            [RSCRIPT_BIN, script, "Validation"],
            capture_output=True,
            encoding="utf-8",
            env=env,
            cwd=PROJECT_ROOT,
        )
        assert result.returncode != 0, \
            "Expected non-zero exit when R script called directly without RENV_PATHS_ROOT"
        out = (result.stdout or "") + (result.stderr or "")
        assert "RENV_PATHS_ROOT" in out, \
            f"Expected 'RENV_PATHS_ROOT' in error output:\n{out}"

    def test_tc_core_oq_005_python_bypass_protection(self):
        """
        TC-CORE-OQ-005 (OQ-10):
        Calling a Python script directly with system python3 (venv excluded
        from PATH) exits non-zero. The script first checks that VENV_PATH and
        JR_PROJECT_ROOT are set (only jrrun sets them) and stops with a clear
        message; behind that guard, a missing validated package is caught as
        ImportError and also exits 1.
        """
        script = os.path.join(PROJECT_ROOT, "Python", "jrc_py_hello.py")
        project_id = _project_id()
        venv_bin = os.path.expanduser(f"~/.venvs/{project_id}/{VENV_BIN_DIR}")
        path_dirs = [p for p in os.environ.get("PATH", "").split(PATH_SEP) if p != venv_bin]
        env = {**os.environ, "PATH": PATH_SEP.join(path_dirs)}
        result = subprocess.run(
            [PYTHON_BIN, script, "Validation"],
            capture_output=True,
            encoding="utf-8",
            env=env,
            cwd=PROJECT_ROOT,
        )
        assert result.returncode != 0, \
            "Expected non-zero exit when Python script called without the validated venv"
        out = result.stdout + result.stderr
        assert any(kw in out for kw in ("VENV_PATH / JR_PROJECT_ROOT not set",
                                        "Required package", "ImportError", "No module")), \
            f"Expected guard or import error message in output:\n{out}"
