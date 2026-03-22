# Troubleshooting — JR Validated Environment

This document covers the most common issues encountered when installing,
running, or validating the JR environment. Each entry describes the symptom,
likely cause, and resolution steps.

---

## Table of Contents

1. [Dropbox not synced](#1-dropbox-not-synced)
2. [Wrong R or Python version installed](#2-wrong-r-or-python-version-installed)
3. [renv library empty after rebuild](#3-renv-library-empty-after-rebuild)
4. [Integrity check failing](#4-integrity-check-failing)
5. [PATH not set up correctly](#5-path-not-set-up-correctly)
6. [Packages loading from system library instead of renv](#6-packages-loading-from-system-library-instead-of-renv)
7. [pip install failing during venv rebuild](#7-pip-install-failing-during-venv-rebuild)
8. [RENV_PATHS_ROOT not set error](#8-renv_paths_root-not-set-error)
9. [Rscript not found](#9-rscript-not-found)
10. [project_id.txt not found](#10-project_idtxt-not-found)
11. [validate_R_env.R not found](#11-validate_r_envr-not-found)
12. [Two copies of JR Anchored installed on the same machine](#12-two-copies-of-jr-anchored-installed-on-the-same-machine)

---

## 1. Dropbox not synced

**Symptom**

`admin_install_R` or `admin_install_Python` fails with a message like:

```
❌ Local repo not found at: /Users/.../R_repo/my-cran-repo
   Run admin_install_R --rebuild first to create it.
```

**Cause**

The local package repository lives in Dropbox and has not finished syncing
to this machine, or Dropbox is not running.

**Resolution**

1. Open Dropbox and confirm it is running and signed in.
2. Navigate to the `R_repo/` or `Python_repo/` folder in Finder and wait
   for the sync indicator to show a green tick on all files.
3. If the folder is missing entirely, check that the Dropbox account is the
   correct one and that the folder has been shared with you.
4. Run `admin_install_R` or `admin_install_Python` again once sync is complete.

---

## 2. Wrong R or Python version installed

**Symptom — R**

```
❌ R 4.5 required, found 4.4
   Install correct R version from .../R_repo/
```

**Symptom — Python**

```
❌ Python 3.11.9 required, found 3.12.0
   Install Python from .../Python_repo/
   Double-click the .pkg and follow the installer steps.
```

**Cause**

The system R or Python version does not match the version pinned in
`admin/r_version.txt` or `admin/python_version.txt`.

**Resolution**

1. Locate the correct installer in `R_repo/` or `Python_repo/` in Dropbox.
2. Install the correct version. Multiple R and Python versions can coexist
   on macOS — installing the correct version will not remove the existing one.
3. For R: download the correct `.pkg` from the R_repo and install it.
4. For Python: `admin_install_Python` uses a version-specific binary
   (e.g. `python3.11`) so the correct minor version must be installed.
5. Re-run the admin install script.

---

## 3. renv library empty after rebuild

**Symptom**

`admin_install_R` completes without errors but user wrappers immediately
trigger a rebuild, or `jr_versions` shows packages as NOT INSTALLED.

**Cause**

The renv library path contains an empty or partial installation. This can
happen if a previous install was interrupted, or if the library path has
changed (e.g. after a PROJECT_ID change).

**Resolution**

1. Check the renv library path:
```zsh
ls ~/.renv/MyProject/renv/library/
```
2. If the folder is missing or empty, delete it and re-run:
```zsh
rm -rf ~/.renv/MyProject
admin_install_R
```
3. If the issue persists after a clean install, run with `--rebuild` to
   re-download all packages from the local repo:
```zsh
admin_install_R --rebuild
```
   Note: `--rebuild` re-downloads from the local Dropbox repo only — it does
   not access the internet unless `BUILD_REPO=true` is also set.

---

## 4. Integrity check failing

**Symptom**

```
❌ PROJECT INTEGRITY CHECK FAILED
   Modified or missing files:
   /Users/.../R/calctltf.R
```

**Cause**

One or more project files have been modified since the integrity hash was
last generated. This may be intentional (a file was legitimately updated)
or unintentional (accidental edit, file corruption, or sync conflict).

**Resolution**

1. Review the listed files carefully. If the change was unintentional,
   restore the file from git:
```zsh
git checkout R/calctltf.R
```
2. If the change was intentional and reviewed, regenerate the integrity
   file as admin:
```zsh
admin_create_hash
```
3. If multiple files are listed and the cause is unclear, check git status:
```zsh
git status
git diff
```
4. Never regenerate the integrity file without reviewing and approving all
   listed changes — this is a Quality event.

---

## 5. PATH not set up correctly

**Symptom**

```
zsh: command not found: jrrun
zsh: command not found: jr_versions
```

**Cause**

`setup_jr_path.sh` has not been run, or the Terminal window was not
reopened after running it.

**Resolution**

1. Run the path setup script from the project root:
```zsh
./setup_jr_path.sh
```
2. Open a **new Terminal window** — PATH changes do not apply to the current
   window.
3. Verify the PATH entry was added:
```zsh
grep "JR Validated Environment" ~/.zprofile
```
   You should see:
```
# JR Validated Environment — begin
export PATH="$PATH:/path/to/your/project"
# JR Validated Environment — end
```
4. If the entry is present but scripts are still not found, confirm the
   project folder path in `.zprofile` matches the actual project location.

---

## 6. Packages loading from system library instead of renv

**Symptom**

`validate_R_env` reports a package is loading from a path outside the
validated renv library, such as `/Library/Frameworks/R.framework/...`
instead of `~/.renv/MyProject/renv/library/...`.

**Cause**

One or more of the R library override environment variables (`R_LIBS`,
`R_LIBS_USER`, `R_LIBS_SITE`) is set in the shell environment, overriding
the renv library path. This is the most common cause of packages being found
outside the validated library.

**Resolution**

1. Check for conflicting environment variables:
```zsh
echo $R_LIBS
echo $R_LIBS_USER
echo $R_LIBS_SITE
```
2. If any are set, locate where they are defined:
```zsh
grep -r "R_LIBS" ~/.zprofile ~/.zshrc ~/.Renviron 2>/dev/null
```
3. Remove or comment out any `R_LIBS*` exports that are not part of the
   JR environment setup.
4. The JR wrappers (`jrr`, `jrpy`) always unset these variables before
   calling Rscript — if the issue only occurs when running scripts directly
   with `Rscript`, that is expected behaviour. Always use the wrappers.

---

## 7. pip install failing during venv rebuild

**Symptom**

`admin_install_Python` fails during the pip install step with an error such as:

```
ERROR: Could not find a version that satisfies the requirement matplotlib==3.8.2
ERROR: No matching distribution found for matplotlib==3.8.2
```

**Cause**

The package file is missing from the local Python repo (`Python_repo/my-repo/`),
or the Dropbox sync is incomplete.

**Resolution**

1. Check the local repo contains the expected wheel or sdist file:
```zsh
ls Python_repo/my-repo/ | grep matplotlib
```
2. If the file is missing, wait for Dropbox to finish syncing and try again.
3. If the file is genuinely absent (e.g. after adding a new package without
   running `--add`), run:
```zsh
admin_install_Python --add matplotlib==3.8.2
```
4. If the repo was built on a different platform (e.g. Intel vs Apple Silicon),
   the wheel file may be incompatible. Contact your administrator to rebuild
   the repo on the correct platform.

---

## 8. RENV_PATHS_ROOT not set error

**Symptom**

Running an R script directly with `Rscript` produces:

```
Error: RENV_PATHS_ROOT is not set.
Run this script from the provided zsh wrapper.
```

**Cause**

This is expected behaviour, not a bug. The JR environment requires scripts
to be run through their zsh wrappers (e.g. `jrrun`, `jrc_R_hello`) so that
`RENV_PATHS_ROOT` and other environment variables are set correctly before
R starts.

**Resolution**

Always run scripts through their wrapper:

```zsh
# Correct
jrr R/calctltf.R mydata.csv

# Incorrect — will fail with the above error
Rscript --vanilla R/calctltf.R mydata.csv
```

If you need to run a script interactively in RStudio or similar, contact
your administrator — a separate setup is required for interactive use.

---

## 9. Rscript not found

**Symptom**

```
❌ Rscript not found.
   Install R from: .../R_repo/
```

**Cause**

R is not installed on this machine, or the R installation is not on the PATH.

**Resolution**

1. Check whether R is installed:
```zsh
which Rscript
ls /Library/Frameworks/R.framework/Versions/
```
2. If R is installed but not found, the PATH may be incomplete. R installers
   on macOS add `/usr/local/bin/Rscript` — check this exists:
```zsh
ls -la /usr/local/bin/Rscript
```
3. If R is not installed, obtain the correct installer from `R_repo/` in
   Dropbox. The required version is in `admin/r_version.txt`.

---

## 10. project_id.txt not found

**Symptom**

```
❌ project_id.txt not found at: /Users/.../admin/project_id.txt
   Contact your administrator.
```

**Cause**

The `project_id.txt` file is missing from the `admin/` folder. This file
is committed to Git and should always be present after cloning the repository.

**Resolution**

1. Check whether the file exists:
```zsh
ls admin/project_id.txt
```
2. If missing after a fresh clone, the clone may be incomplete. Try:
```zsh
git status
git pull
```
3. If the file was accidentally deleted, restore it from git:
```zsh
git checkout admin/project_id.txt
```
4. If none of the above resolves the issue, contact your administrator to
   confirm the correct `PROJECT_ID` value and recreate the file manually:
```zsh
echo "MyProject" > admin/project_id.txt
```

---

## 12. Two copies of JR Anchored installed on the same machine

**Symptom**

You have cloned JR Anchored into a second folder (e.g. for testing a new
release). After running `setup_jr_path.sh` in the second copy, running
`jr_versions` or any wrapper still executes the script from the **first**
installation.

**Cause**

Both installations add their `bin/` and `wrapper/` directories to `PATH`.
The shell searches `PATH` entries in order and stops at the first match,
so the first-installed copy always wins when commands are entered by name.

**Resolution**

This is expected shell behaviour. For most users there is only ever one
installation per machine and this is not an issue.

If you genuinely need to run commands from a second copy:

1. Use explicit paths:
```zsh
~/path/to/second-copy/bin/jr_versions
```
2. Or `cd` into the second copy and call scripts with `./`:
```zsh
cd ~/path/to/second-copy
./bin/jr_versions
```

To switch which installation is active long-term, edit `~/.zprofile` (macOS)
or `~/.bashrc` (Windows Git Bash) and move the desired installation's `PATH`
entry to appear first.

**Important — Project ID conflict**

If both installations share the same `admin/project_id.txt` value, they also
share the same renv library (`~/.renv/<PROJECT_ID>/`), Python venv
(`~/.venvs/<PROJECT_ID>/`), run log, and validation evidence folder. If the
two installations have identical `renv.lock` and `python_requirements.txt`
files this is harmless. However, if the package versions differ — for example
when testing a new release alongside a production copy — each installation
will see the other's library as stale and trigger a rebuild, overwriting the
shared library. The two installations will continuously break each other.

To avoid this, give the test installation a distinct Project ID before running
any scripts:

```zsh
echo "MyProject-test" > admin/project_id.txt
admin_create_hash
```

This ensures each installation maintains its own isolated renv library, venv,
and audit log.

---

## 11. validate_R_env.R not found

**Symptom**

`jr_env_check` fails with:

```
❌ admin/R/validate_R_env.R not found.
   Run admin_validate first to generate it.
```

**Cause**

The validation scripts (`admin/R/validate_R_env.R` and
`admin/Python/validate_Python_env.py`) are auto-generated and excluded from
Git. They must be generated by the administrator before users can run
`jr_env_check`.

**Resolution**

Ask your administrator to run:

```zsh
admin_validate
```

This regenerates both validation scripts and runs a full IQ/OQ/PQ check.
The generated scripts will then be available for `jr_env_check`.

Note: this is by design — the validation scripts are generated from
`generate_validate_R.zsh` and `generate_validate_Python.zsh`, which are
the version-controlled source of truth. Only the administrator can regenerate
them to ensure the validation logic matches the approved configuration.
