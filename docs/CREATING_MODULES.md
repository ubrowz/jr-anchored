# Creating a New Module

This guide walks through adding a new module repository to JR Anchored.
A module is a self-contained collection of related scripts that lives under
`repos/<module>/`, with its own wrappers, help files, OQ test suite, and
validation evidence.

The built-in modules (`repos/msa/`, `repos/spc/`, `repos/corr/`, `repos/as/`)
are the reference implementations. When in doubt, look at how they are built.

---

## Contents

1. [What is a module?](#1-what-is-a-module)
2. [Prerequisites](#2-prerequisites)
3. [Step 1 — Create the module scaffold](#3-step-1--create-the-module-scaffold)
4. [Step 2 — Add an R script](#4-step-2--add-an-r-script)
5. [Step 3 — Fill in the R script](#5-step-3--fill-in-the-r-script)
6. [Step 4 — Add OQ test data](#6-step-4--add-oq-test-data)
7. [Step 5 — Write OQ tests](#7-step-5--write-oq-tests)
8. [Step 6 — Run the OQ suite](#8-step-6--run-the-oq-suite)
9. [Step 7 — Regenerate the integrity file](#9-step-7--regenerate-the-integrity-file)
10. [Module directory reference](#10-module-directory-reference)
11. [OQ test conventions](#11-oq-test-conventions)

---

## 1. What is a module?

A module groups related scripts that share a common purpose. Examples:

| Module | Purpose |
|--------|---------|
| `msa`  | Measurement System Analysis (Gauge R&R, Type 1, Attribute) |
| `spc`  | Statistical Process Control charts |
| `corr` | Correlation and regression analysis |
| `as`   | Acceptance Sampling |

Each module:

- Has its own subdirectory under `repos/`
- Adds its `wrapper/` folder to PATH automatically (via `setup_jr_path.sh`)
- Has its own OQ test suite and evidence file
- Can be developed and validated independently

---

## 2. Prerequisites

- JR Anchored is installed and working (`jr_versions` runs without error)
- You are working in the project root directory
- Admin commands are available on your PATH (run `setup_jr_path.sh` first if not)

---

## 3. Step 1 — Create the module scaffold

Run `admin_create_repo` with your chosen module name. Use lowercase letters
and underscores only.

```bash
./admin/admin_create_repo capability
```

This creates the full directory structure under `repos/capability/` and
generates three ready-to-use admin scripts for that module:

```
repos/capability/
├── R/                               ← R scripts go here
├── wrapper/                         ← wrappers (auto-added to PATH)
├── help/                            ← help text files
├── sample_data/                     ← example data for users
├── docs/                            ← validation documents
├── oq/
│   ├── conftest.py                  ← shared OQ helpers (ready to use)
│   ├── requirements.txt             ← pytest pin
│   ├── python_version.txt           ← Python version for OQ venv
│   ├── data/                        ← test data CSVs
│   └── test_capability_example.py  ← example test to adapt
├── admin_capability_scaffold_R      ← add R scripts to this module
├── admin_capability_scaffold_Python ← add Python scripts to this module
└── admin_capability_oq              ← run the OQ suite
```

> **PATH note:** After running `setup_jr_path.sh` once (or reopening your
> terminal), `repos/capability/wrapper/` is automatically on your PATH.
> Scripts you add to this module are immediately callable by name.

---

## 4. Step 2 — Add an R script

Use the module's own scaffold script to create a new R script inside the
module:

```bash
repos/capability/admin_capability_scaffold_R jrc_capability_cpk
```

This creates:

```
repos/capability/R/jrc_capability_cpk.R        ← script template
repos/capability/wrapper/jrc_capability_cpk    ← wrapper (executable)
repos/capability/help/jrc_capability_cpk.txt   ← help file template
```

The wrapper is pre-configured with the correct path to `jrrun`
(`../../../bin/jrrun`) and is immediately executable.

For Python scripts, use `admin_capability_scaffold_Python` instead —
it follows the same pattern and creates a `.py` template.

---

## 5. Step 3 — Fill in the R script

Open `repos/capability/R/jrc_capability_cpk.R`. The template already contains:

- The `RENV_PATHS_ROOT` check that enforces running through the wrapper
- The `.libPaths()` setup to use the validated renv library
- Argument parsing scaffolding
- `message()` output structure

The main things to fill in:

**Library imports** — add any required packages to `suppressPackageStartupMessages({})`:
```r
suppressPackageStartupMessages({
  library(qcc)
})
```

If a new package is needed, add it to `admin/R_requirements.txt` and run:
```bash
./admin/admin_install_R --add qcc==2.7
```

**Argument validation** — parse `commandArgs(trailingOnly = TRUE)` and
validate types, ranges, and file existence before doing any computation.

**Main logic** — write results to `message()` (goes to stderr, captured by
the OQ test runner) so that stdout is clean for any downstream use.

**Help file** — update `repos/capability/help/jrc_capability_cpk.txt` with
the real argument descriptions and a working example. This is what users see
when they run `jrc_capability_cpk --help`.

Test the script manually before writing OQ tests:

```bash
jrc_capability_cpk mydata.csv 0.95
```

---

## 6. Step 4 — Add OQ test data

Place test CSV files in `repos/capability/oq/data/`. Each file should test
a specific condition — a typical set for one script:

| File | Purpose |
|------|---------|
| `capability_normal.csv`     | Standard valid input — happy path |
| `capability_tight.csv`      | Data near the boundary — edge case |
| `capability_small.csv`      | Too few rows — should trigger an error |
| `capability_nonnumeric.csv` | Non-numeric values — should trigger an error |

CSV files must have `id` and `value` columns (the JR data convention):

```csv
id,value
1,10.2
2,10.5
3,9.8
```

Add at least one valid file and one file that should cause the script to
exit non-zero.

---

## 7. Step 5 — Write OQ tests

Rename or replace `repos/capability/oq/test_capability_example.py` with
your real test file. One file per script is the convention:

```
repos/capability/oq/test_capability_cpk.py
```

### What conftest.py provides

Every module's `conftest.py` exports three helpers that you import at the
top of each test file:

```python
from conftest import run, combined, data
```

| Helper | What it does |
|--------|-------------|
| `run(script, *args)` | Calls `jrrun <script> <args...>` and returns the `CompletedProcess` result |
| `combined(result)` | Returns `stdout + stderr` as one string — use this for pattern matching |
| `data(filename)` | Returns the full path to a file in `oq/data/` |

### Test file structure

```python
"""
OQ test suite — capability module: jrc_capability_cpk

Maps to validation plan JR-VP-CAP-001 as follows:

  TC-CAP-C-001  Valid input -> exit 0, "Cpk" in output
  TC-CAP-C-002  Cpk value present in output
  TC-CAP-C-003  No arguments -> non-zero exit, usage in output
  TC-CAP-C-004  File not found -> non-zero exit
  TC-CAP-C-005  Too few rows -> non-zero exit
  TC-CAP-C-006  Direct Rscript call without RENV_PATHS_ROOT -> non-zero exit
"""

import os
import subprocess
from conftest import PROJECT_ROOT, MODULE_ROOT, run, combined, data


class TestCapabilityCpk:

    def test_tc_cap_c_001_happy_path_exits_zero(self):
        """TC-CAP-C-001: valid input -> exit 0, 'Cpk' in output."""
        r = run("jrc_capability_cpk", data("capability_normal.csv"), "0.95")
        assert r.returncode == 0, combined(r)
        assert "Cpk" in combined(r)

    def test_tc_cap_c_002_cpk_value_present(self):
        """TC-CAP-C-002: output must contain a numeric Cpk value."""
        r = run("jrc_capability_cpk", data("capability_normal.csv"), "0.95")
        assert "Cpk:" in combined(r)

    def test_tc_cap_c_003_no_args_exits_nonzero(self):
        """TC-CAP-C-003: no arguments -> non-zero exit, usage shown."""
        r = run("jrc_capability_cpk")
        assert r.returncode != 0
        assert "Usage" in combined(r) or "usage" in combined(r)

    def test_tc_cap_c_004_missing_file_exits_nonzero(self):
        """TC-CAP-C-004: missing data file -> non-zero exit."""
        r = run("jrc_capability_cpk", "nonexistent.csv", "0.95")
        assert r.returncode != 0

    def test_tc_cap_c_005_too_few_rows_exits_nonzero(self):
        """TC-CAP-C-005: data with too few rows -> non-zero exit."""
        r = run("jrc_capability_cpk", data("capability_small.csv"), "0.95")
        assert r.returncode != 0

    def test_tc_cap_c_006_bypass_protection(self):
        """TC-CAP-C-006: direct Rscript call without RENV_PATHS_ROOT -> non-zero exit."""
        script = os.path.join(MODULE_ROOT, "R", "jrc_capability_cpk.R")
        env = {k: v for k, v in os.environ.items() if k != "RENV_PATHS_ROOT"}
        result = subprocess.run(
            ["Rscript", "--vanilla", script, data("capability_normal.csv"), "0.95"],
            capture_output=True, encoding="utf-8", env=env, cwd=PROJECT_ROOT,
        )
        assert result.returncode != 0
        assert "RENV_PATHS_ROOT" in (result.stdout + result.stderr)
```

### Minimum test set for each script

Every script should have at minimum:

| Test case | What it checks |
|-----------|---------------|
| Happy path | Valid input exits 0 and produces expected output |
| Key output present | The main result label or value appears in the output |
| No arguments | Non-zero exit, usage message shown |
| File not found | Non-zero exit |
| Bypass protection | Direct `Rscript` call without `RENV_PATHS_ROOT` exits non-zero |

Error cases that are specific to your script (invalid range, wrong column
count, non-numeric values, etc.) should each have their own test case.

---

## 8. Step 6 — Run the OQ suite

```bash
repos/capability/admin_capability_oq
```

This sets up the shared OQ venv (first run only), runs pytest against
`repos/capability/oq/`, and writes a timestamped evidence file to:

```
~/.jrscript/<PROJECT_ID>/validation/capability_oq_execution_<timestamp>.txt
```

All tests must pass before the module is considered validated. Fix any
failures before proceeding.

To run a single test file during development:

```bash
repos/capability/admin_capability_oq repos/capability/oq/test_capability_cpk.py
```

To run with more detail on failures:

```bash
repos/capability/admin_capability_oq -v --tb=long
```

---

## 9. Step 7 — Regenerate the integrity file

After all scripts, wrappers, and help files are in place and the OQ suite
passes, regenerate the project integrity file:

```bash
./admin/admin_create_hash
```

This updates `admin/project_integrity.sha256` to include all the new files.
Every subsequent script run will verify against this hash — any modification
to a project file will be caught before the script executes.

---

## 10. Module directory reference

```
repos/<module>/
├── R/                        ← R analysis scripts (jrc_<module>_<name>.R)
├── Python/                   ← Python scripts (jrc_<module>_<name>.py) — optional
├── wrapper/                  ← one wrapper per script (executable, no extension)
├── help/                     ← one help file per script (<name>.txt)
├── sample_data/              ← example CSVs for users to test with
├── docs/                     ← validation plan, validation report, user manual
├── oq/
│   ├── conftest.py           ← shared helpers (run, combined, data)
│   ├── requirements.txt      ← pytest version pin
│   ├── python_version.txt    ← Python version for the OQ venv
│   ├── data/                 ← test data CSVs used by the OQ tests
│   └── test_<module>_*.py   ← one test file per script
├── admin_<module>_scaffold_R       ← creates R script + wrapper + help
├── admin_<module>_scaffold_Python  ← creates Python script + wrapper + help
└── admin_<module>_oq               ← runs the OQ suite, writes evidence
```

---

## 11. OQ test conventions

**Test case ID format:** `TC-<MODULE>-<LETTER>-<NNN>`

- `<MODULE>` — uppercase module abbreviation, up to 4 characters (e.g. `CAP`, `MSA`, `CORR`)
- `<LETTER>` — one letter identifying the script within the module (A, B, C, …)
- `<NNN>` — zero-padded sequence number (001, 002, …)

Example: `TC-CAP-C-001` is the first test case for script C in the
capability module.

**Test method naming:** `test_tc_<module>_<letter>_<nnn>_<description>`

```python
def test_tc_cap_c_001_happy_path_exits_zero(self):
```

**One class per script**, named `Test<Module><ScriptSuffix>`:

```python
class TestCapabilityCpk:
```

**Docstring must contain the TC ID** so it appears in the pytest output
and in the evidence file:

```python
def test_tc_cap_c_001_happy_path_exits_zero(self):
    """TC-CAP-C-001: valid input -> exit 0, 'Cpk' in output."""
```

**File header must list all TC IDs** with a one-line description — this
mapping is the link between the evidence file and the validation plan:

```python
"""
OQ test suite — capability module: jrc_capability_cpk

Maps to validation plan JR-VP-CAP-001 as follows:

  TC-CAP-C-001  Valid input -> exit 0, "Cpk" in output
  TC-CAP-C-002  Cpk value present in output
  ...
"""
```

**Reference implementation:** `repos/corr/oq/test_corr_pearson.py` is the
most complete worked example — 11 test cases covering all standard patterns
including output value checking and bypass protection.
