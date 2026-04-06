# jr_helpers.py
# Imported by JR Anchored Python scripts at startup (via jrrun).
# Provides jr_log_output_hashes() for logging output file SHA-256 hashes
# to the run log after a script completes.
#
# Requires env vars set by jrrun:
#   JR_PROJECT_ROOT  — project root directory
#   PROJECT_ID       — project identifier (used to locate run.log)

import hashlib
import os
import warnings
from datetime import datetime
from pathlib import Path


def jr_log_output_hashes(files):
    project_id = os.environ.get("PROJECT_ID", "")
    if not project_id:
        warnings.warn("jr_log_output_hashes: PROJECT_ID not set — output hashes not logged.")
        return
    log_file = Path.home() / ".jrscript" / project_id / "run.log"
    timestamp = datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
    for f in files:
        path = Path(f)
        if not path.exists():
            warnings.warn(f"jr_log_output_hashes: file not found, skipping: {f}")
            continue
        try:
            sha256 = hashlib.sha256(path.read_bytes()).hexdigest()
        except OSError as e:
            warnings.warn(f"jr_log_output_hashes: could not hash file {f}: {e}")
            continue
        with log_file.open("a", encoding="utf-8") as fh:
            fh.write(f"{timestamp}\tjrrun_output\t{path.name}\t{sha256}\n")
