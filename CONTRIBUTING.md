# Contributing to JR Anchored

> **Maintainer-led project.** JR Anchored is developed and maintained by
> a single maintainer. Architecture, roadmap, and validation decisions rest
> with the maintainer. The most effective way to contribute is to
> **open an issue** — PRs submitted without prior discussion may be closed
> without review. This repository is public for transparency and
> discoverability, not as an invitation for unsolicited structural changes.

Thank you for your interest in contributing. There are three levels of
contribution depending on how widely you want to share your work.

---

## Table of Contents

1. [Three levels of contribution](#three-levels-of-contribution)
2. [Contributing Community Scripts](#contributing-community-scripts)
3. [Before You Start](#before-you-start)
4. [Setting Up a Development Environment](#setting-up-a-development-environment)
5. [Branch Naming Conventions](#branch-naming-conventions)
6. [Commit Message Format](#commit-message-format)
7. [Linting Shell Scripts](#linting-shell-scripts)
8. [Pull Request Process](#pull-request-process)
9. [What We Will and Will Not Accept](#what-we-will-and-will-not-accept)

---

## Three levels of contribution

### Level 1 — Personal use (no admin required)

If you have written an R or Python script for your own analysis, you can
run it immediately in the validated environment using `jrrun`:

```bash
jrrun ./myscript.R mydata.csv
jrrun ./myanalysis.py mydata.csv
```

Your script runs with the same pinned packages and integrity-checked
infrastructure as the community scripts. No changes to the project are
needed and no admin action is required.

---

### Level 2 — Team contribution (admin required)

If your script is useful to the wider team and you want it to become an
official community script, ask your administrator to add it.

**Your responsibilities:**
- Provide the finished R or Python script.
- Provide the help text — what the script does, what arguments it takes,
  and a usage example. The administrator will use this to populate the
  help file.

**What the administrator does:**
1. Runs `admin_scaffold_R jrc_yourscript` (or `admin_scaffold_Python`)
   to create the script template, wrapper, and help file.
2. Copies your script content in and fills in the help file.
3. If new packages are required, adds them:
   ```bash
   ./admin/admin_install_R --add packagename==1.2.3
   ```
4. Regenerates the integrity file and runs the OQ suite to confirm all
   tests still pass.
5. Updates `CHANGELOG.md` and commits.

The script is then available to all team members on their next sync.

> **Note on revalidation:** Adding a community script is a change to the
> validated configuration. The administrator must confirm that the OQ test
> suite passes in full before the script is used in a regulated context.

---

### Level 3 — Public contribution (GitHub)

If your script could be useful to organisations beyond your own team,
you are welcome to contribute it to this repository. Open an issue
first to discuss the proposal — see
[Contributing Community Scripts](#contributing-community-scripts) below
for the full process.

**What contributors provide vs what the maintainer handles:**

| Contributor | Maintainer |
|---|---|
| R or Python script(s) | Wrapper scripts |
| Help text file(s) | OQ test suite and validation documents |
| Sample data CSV(s) | python-docx generators and PDF production |
| Algorithm description / references | Website integration (7 pages) |
| | GUI wiring (`app/jr_app.py`) |
| | Integrity hash regeneration |
| | Release commit and version bump |

Integration into the validated environment — OQ tests, validation plan,
validation report, user manual, web pages, GUI, and release — is handled
by the maintainer. Contributors do not need to know the project's
validation framework or web structure.

---

## Contributing Community Scripts

Community scripts are the R and Python analysis scripts in `R/` and
`Python/`. If you have a validated analysis script that is statistically
sound and broadly applicable to design verification workflows, here is
how to contribute it.

If your contribution is a **group of related scripts** (for example a
new analysis domain like capability analysis or DoE), it will be
integrated as a **module** under `repos/<module>/`. The integration
work is handled by the maintainer — see the contributor/maintainer
split above.

### Step 1 — Open a GitHub issue

Before writing code, open an issue describing:
- What the script does and which statistical method it implements.
- When an engineer would use it (the decision point in a design
  verification workflow).
- What inputs it expects (argument list) and what outputs it produces
  (terminal output, PNG, etc.).
- Any R or Python packages it requires that are not already in
  `admin/R_requirements.txt` or `admin/python_requirements.txt`.
- Key references (standards, papers, textbooks) that the method is
  based on — these feed into the validation plan and the references
  page.

This gives the maintainer a chance to confirm the script fits the
project's scope and conventions before you invest time writing it.

### Step 2 — Develop the script and help text

What you need to provide:

| Artefact | Notes |
|---|---|
| Script(s) | Follow the `jrc_` naming prefix. Check `RENV_PATHS_ROOT` at startup and `stop()` if not set. Write PNG output to `~/Downloads/` with a timestamped filename. Exit non-zero on all error conditions. |
| Help text | Plain text for each script: USAGE, DESCRIPTION, ARGUMENTS, OUTPUT, and at least one EXAMPLE. See existing `help/` files for the format. |
| Sample data | One or two small CSV files a user could run the script against to see a realistic result. Use the standard two-column `id, value` format where the script allows it. |

You do **not** need to provide wrappers, OQ tests, validation
documents, or web page edits. The maintainer handles all of that.

### Step 3 — Submit a pull request

Submit a pull request with the script(s), help file(s), and sample
data. Reference the issue. The maintainer will:
- Review the statistical method for correctness and appropriate scope.
- Assess the help text for clarity and completeness.
- Build the full integration: wrapper, OQ suite, validation documents,
  GUI wiring, and web updates.

Accepted scripts are included in a future minor release with a
CHANGELOG entry, full OQ validation evidence, and updated
documentation.

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

macOS (Apple Silicon or Intel):
- R — version specified in `admin/r_version.txt`
- Python — version specified in `admin/python_version.txt`
- shellcheck — for linting shell scripts: `brew install shellcheck`
- Git

Windows 10/11:
- R for Windows — version specified in `admin/r_version.txt`
- Python for Windows — version specified in `admin/python_version.txt`
- Git for Windows (Git Bash)

Both platforms:
- An SMB network share for the local package repository

**Steps:**

1. Fork the repository on GitHub.

2. Clone your fork:
```bash
git clone https://github.com/<your-username>/jr-anchored.git
cd jr-anchored
```

3. Add the upstream remote so you can pull future changes:
```bash
git remote add upstream https://github.com/ubrowz/jr-anchored.git
```

4. Set up your local package repository. Since `R_repo/` and `Python_repo/`
   are excluded from Git, you need to build them from scratch or obtain them
   from a team member:
```bash
./admin/admin_install_R --rebuild
./admin/admin_install_Python --rebuild
```

5. Run `setup_jr_path.sh` to add the project to your PATH:
```bash
./setup_jr_path.sh
```
   Then open a new Terminal window.

6. Verify everything is working:
```bash
./admin/admin_validate
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

fix: capture CALL_DIR before cd in jrrun

docs: add troubleshooting entry for renv library empty after rebuild

refactor: simplify renv rebuild condition check
```

Keep the summary line under 72 characters. Use the body to explain the
reasoning behind the change if it is not obvious from the summary.

---

## Linting Shell Scripts

All shell scripts must pass `shellcheck` before submission. Run it on any
script you have modified:

```bash
shellcheck -s bash myscript
```

To lint all scripts in the project at once:

```bash
find . -maxdepth 2 -type f -perm -111 ! -name "*.R" ! -name "*.py" \
  | xargs shellcheck -s bash
```

Pull requests that introduce shellcheck warnings will be asked to resolve
them before merging.

---

## Pull Request Process

1. Make sure your branch is up to date with upstream main before opening
   a pull request:
```bash
git fetch upstream
git rebase upstream/main
```

2. Run shellcheck on all modified scripts.

3. If you modified any requirements files, re-run `admin_validate` to
   regenerate the validation scripts and confirm the environment is consistent:
```bash
./admin/admin_validate
```

4. If you added or modified any scripts or wrappers, re-generate the
   integrity file:
```bash
./admin/admin_create_hash
```

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
- Support for Linux, provided macOS and Windows behaviour is not degraded
- Performance improvements to the admin or rebuild scripts
- New example R or Python scripts that demonstrate validated environment usage
- Community scripts submitted with a script, help file, and sample data
  (the maintainer handles validation integration — see
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
  standard macOS (Homebrew) or Windows (Git for Windows) tooling

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


