# Contributing to JR Validated Environment

Thank you for your interest in contributing. This document explains how to
get started, what we expect from contributions, and what kinds of changes
are and are not accepted.

---

## Table of Contents

1. [Before You Start](#before-you-start)
2. [Setting Up a Development Environment](#setting-up-a-development-environment)
3. [Branch Naming Conventions](#branch-naming-conventions)
4. [Commit Message Format](#commit-message-format)
5. [Linting zsh Scripts](#linting-zsh-scripts)
6. [Pull Request Process](#pull-request-process)
7. [What We Will and Will Not Accept](#what-we-will-and-will-not-accept)
8. [Contributing Community Scripts](#contributing-community-scripts)

---

## Before You Start

Please open an **issue before submitting a pull request** so the proposed
change can be discussed. This avoids situations where significant work is
done on a change that turns out to be out of scope or in conflict with the
project's direction.

For small fixes (typos, documentation corrections, obvious bugs) you may
submit a pull request directly without an issue.

---

## Setting Up a Development Environment

**Requirements:**
- macOS 12 Ventura or later (Apple Silicon or Intel)
- Xcode Command Line Tools: `xcode-select --install`
- R — version specified in `admin/r_version.txt`
- Python — version specified in `admin/python_version.txt`
- Dropbox — for the local package repository
- shellcheck — for linting zsh scripts: `brew install shellcheck`
- Git

**Steps:**

1. Fork the repository on GitHub.

2. Clone your fork:
```zsh
git clone https://github.com/<your-username>/jr-validated-environment.git
cd jr-validated-environment
```

3. Add the upstream remote so you can pull future changes:
```zsh
git remote add upstream https://github.com/yourorg/jr-validated-environment.git
```

4. Set up your local package repository. Since `R_repo/` and `Python_repo/`
   are excluded from Git, you need to build them from scratch or obtain them
   from a team member:
```zsh
export LOCAL_REPO="$PWD/R_repo/my-cran-repo"
BUILD_REPO=true ./admin_install_R
./admin_install_Python --rebuild
```

5. Run `setup_path.zsh` to add the project to your PATH:
```zsh
./setup_path.zsh
```
   Then open a new Terminal window.

6. Verify everything is working:
```zsh
validate_R_env
validate_Python_env
```

---

## Branch Naming Conventions

Branch names should be lowercase and use hyphens as separators.
Use one of the following prefixes:

| Prefix | Use for |
|---|---|
| `feature/` | New functionality |
| `fix/` | Bug fixes |
| `docs/` | Documentation changes only |
| `refactor/` | Code restructuring with no behaviour change |
| `test/` | Adding or improving tests |
| `release/` | Release preparation |

**Examples:**
```
feature/add-flag-admin-install
fix/renv-library-path-detection
docs/update-troubleshooting-guide
refactor/simplify-rebuild-block
```

---

## Commit Message Format

Use the following format for commit messages:

```
<type>: <short summary in present tense, max 72 characters>

<optional body — explain what and why, not how>
```

**Types:**

| Type | Use for |
|---|---|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `refactor` | Code change with no behaviour change |
| `chore` | Maintenance, dependency updates |
| `test` | Adding or updating tests |

**Examples:**
```
feat: add --add flag to admin_install_R for single package updates

fix: capture CALL_DIR before cd in jrr wrapper

docs: add troubleshooting entry for renv library empty after rebuild

refactor: simplify renv rebuild condition check
```

Keep the summary line under 72 characters. Use the body to explain the
reasoning behind the change if it is not obvious from the summary.

---

## Linting zsh Scripts

All zsh scripts must pass `shellcheck` before submission. Run it on any
script you have modified:

```zsh
shellcheck -s bash myscript
```

Note: shellcheck does not have a native zsh mode — using `-s bash` catches
the vast majority of issues that apply to zsh as well. Be aware that a small
number of zsh-specific constructs (such as 1-based array indexing) may not
be flagged correctly, so review these manually.

To lint all scripts in the project at once:

```zsh
find . -maxdepth 2 -type f -perm -111 ! -name "*.R" ! -name "*.py" \
  | xargs shellcheck -s bash
```

Pull requests that introduce shellcheck warnings will be asked to resolve
them before merging.

---

## Pull Request Process

1. Make sure your branch is up to date with upstream main before opening
   a pull request:
```zsh
git fetch upstream
git rebase upstream/main
```

2. Run shellcheck on all modified scripts.

3. If you modified any requirements files, re-run the generate scripts to
   keep the validation scripts in sync:
```zsh
./generate_validate_R.zsh
./generate_validate_Python.zsh
```

4. If you added or modified any scripts or wrappers, re-generate the
   integrity file:
```zsh
./admin_create_hash
```
   Note: `admin/project_integrity.sha256` is excluded from Git — do not
   commit it. It is listed in `.gitignore` for this reason.

5. Open a pull request against the `main` branch with a clear description
   of what the change does and why. Reference the related issue number
   if one exists (e.g. `Closes #42`).

6. A maintainer will review the pull request. Please respond to review
   comments within a reasonable time. Pull requests with no activity for
   30 days may be closed.

---

## What We Will and Will Not Accept

### Will accept

- Bug fixes with a clear description of the problem and how the fix
  addresses it
- New functionality that is consistent with the validated environment
  philosophy — controlled package installation, integrity checking,
  clear audit trail
- Documentation improvements — clearer wording, missing steps, new
  troubleshooting entries
- Support for additional platforms (Windows, Linux) provided the macOS
  behaviour is not degraded
- Performance improvements to the admin or rebuild scripts
- New example R or Python scripts that demonstrate validated environment usage
- Community scripts submitted with a complete validation package (see
  [Contributing Community Scripts](#contributing-community-scripts))

### Will NOT accept

- Changes that weaken or bypass integrity checking
- Changes that allow packages to be installed from the internet during
  normal user script execution
- Changes that remove the controlled local repository requirement
- Changes that make the validation evidence less transparent or harder
  for a Quality Manager to review
- Breaking changes to the wrapper interface without a deprecation path
- Changes that introduce dependencies on tools not available via
  standard macOS + Xcode CLT + Homebrew

If you are unsure whether a proposed change falls into one of these
categories, open an issue and ask before investing time in the
implementation.

---

## Regulatory Note

This project is used in medical device development contexts where software
validation is a regulatory requirement. Contributors should be aware that
changes to core environment management logic — package installation,
integrity checking, library path enforcement — may have validation
implications for organisations using the tool. Such changes will be reviewed
carefully and will require clear justification and thorough testing before
acceptance.

---

## Contributing Community Scripts

Community scripts are R or Python analysis scripts of general interest that
others in the medical device development community can adopt and validate for
their own use. They live under `R/contrib/` or `Python/contrib/` and are
separate from the core environment scripts.

### Philosophy

A community script submitted to this project cannot be considered validated
for any receiving organisation — validation is always the responsibility of
the organisation using the script in their own regulated context. What a
submitted community script *can* provide is:

- A working, well-documented script
- A complete set of synthetic test data for running the validation
- A reference validation summary that a receiving organisation can use as
  a starting point for their own IQ/OQ/PQ

This makes validation at the receiving organisation as fast and
straightforward as possible.

### Folder Structure

Each community script lives in its own named subfolder and must be submitted
with the following complete package:

```
R/contrib/
  <script_name>/
    <script_name>.R              ← the script itself
    jr<script_name>              ← zsh wrapper
    README.md                    ← description, inputs, outputs,
                                    acceptance criteria
    validation/
      generate_test_data.R       ← or .py for Python scripts
      test_data.csv              ← pre-generated synthetic data
      data_checksums.txt         ← SHA256 of all data files
      expected_output.csv        ← expected output (tabular scripts)
      expected_output.md         ← expected output description
                                    (graphical scripts — see below)
      test_results.txt           ← submitter's actual run output
      validation_summary.md      ← filled-in IQ/OQ/PQ template
```

Pull requests that are missing any of these files will not be merged.

### Naming Convention

Community script wrappers use the `jrc_` prefix to distinguish them from
core environment wrappers:

```
jrc_calc_process_capability
jrc_fit_distribution
jrc_tolerance_interval
```

### Synthetic Test Data

All test data must be synthetically generated — no real patient data, no
proprietary data, no data derived from confidential sources. Synthetic data
must be generated using a documented fixed random seed so that any
organisation can independently reproduce it.

**Data generation scripts** must follow these conventions:

- Write output relative to their own location — no hardcoded paths:

  ```r
  # R — write to the validation/ folder
  out_file <- file.path(
    dirname(normalizePath(
      sub("--file=", "", grep("--file=", commandArgs(trailingOnly=FALSE), value=TRUE))
    )),
    "test_data.csv"
  )
  ```

  ```python
  # Python — write to the validation/ folder
  out_file = Path(__file__).parent / "test_data.csv"
  ```

- Document the seed, distribution, parameters, and intended use in a
  comment block at the top of the script
- Use only base R or Python standard library — no package dependencies

**Standard datasets** from `data/standard/` may be referenced instead of
providing a custom generation script, where appropriate. See
`data/standard/README.md` for available datasets.

**Checksums** must be generated for all data files and committed as
`validation/data_checksums.txt`:

```zsh
cd R/contrib/<script_name>/validation
shasum -a 256 test_data.csv expected_output.csv > data_checksums.txt
```

### Expected Output — Tabular vs Graphical Scripts

**Tabular output** (CSV, TXT): commit the expected output file directly.
The receiving organisation runs the script and performs a file comparison.

**Graphical output** (PNG, PDF): pixel-level rendering varies between
machines and OS versions so binary comparison is not reliable. Instead,
provide an `expected_output.md` file that describes what the output should
contain as a visual checklist. Example:

```markdown
# Expected Output — calc_process_capability

The output PNG should contain:
- [ ] Histogram of the input measurements
- [ ] Normal distribution curve overlaid
- [ ] Vertical lines at LSL and USL
- [ ] Cp and Cpk values displayed in the plot title or legend
- [ ] Pass/fail zone shading (green = within spec, red = outside spec)
- [ ] X axis labelled with the measurement unit
```

The receiving organisation works through this checklist as part of their OQ.

### Validation Summary

The `validation_summary.md` must be a filled-in version of the project's
Validation Plan template (`docs/validation_plan_template.docx`), covering:

- **IQ** (Installation Qualification): confirm the script is present,
  the wrapper is executable, and all required packages are listed in
  `R_requirements.txt` or `python_requirements.txt`
- **OQ** (Operational Qualification): run the script against `test_data.csv`
  and confirm the output matches `expected_output.csv` or the
  `expected_output.md` checklist
- **PQ** (Performance Qualification): document the acceptance criteria and
  confirm the script produces scientifically correct results — this is the
  submitter's responsibility and must be justified in the summary

### Package Requirements

If the community script requires packages not already in the core
`R_requirements.txt` or `python_requirements.txt`, list them in a
`requirements.txt` file in the script's subfolder:

```
# R/contrib/<script_name>/requirements.txt
fitdistrplus==1.1-11
```

The maintainer will review whether to add these packages to the core
requirements or keep them script-specific. Note that adding packages to
the core requirements triggers a new release and affects all users.

### Disclaimer

Community scripts are contributed by third parties and have not been
independently verified by the project maintainers for scientific correctness.
Each organisation adopting a community script is responsible for performing
their own validation. The submitted validation summary is reference material
only — it is not a transferable validation certificate.

This disclaimer must be reproduced at the top of every community script's
`README.md`.
