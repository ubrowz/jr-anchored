# JR Validated Environment

A framework for running validated R and Python scripts in a controlled,
reproducible environment — designed for medical device development teams
working under FDA and ISO 13485 requirements.

---

## What is this?

The JR Validated Environment provides a structured way to:

- Run R and Python analysis scripts with **pinned, auditable package versions**
- Ensure every team member uses **exactly the same packages** regardless of their machine setup
- Install packages exclusively from a **controlled local repository** — never directly from the internet during normal use
- Verify **project integrity** before every script run
- Generate **validation evidence** for auditors with a single command

It is designed for small to medium medical device development teams on macOS who need a pragmatic, FDA-friendly approach to software validation without the overhead of a full enterprise solution.

---

## Requirements

- macOS (Apple Silicon or Intel)
- [R](https://cran.r-project.org/bin/macosx/) — version specified in `admin/r_version.txt`
- [Python](https://www.python.org/downloads/macos/) — version specified in `admin/python_version.txt`
- [Dropbox](https://www.dropbox.com) — for sharing the local package repository across the team
- Xcode Command Line Tools — install by running `xcode-select --install` in Terminal

---

## Quick Start for End Users

> If you are a team member who has been given access to the JR environment by your administrator, follow these steps.

**Step 1** — Make sure Dropbox is installed and fully synced on your Mac.

**Step 2** — Open Terminal. Press `Command + Space`, type `Terminal`, press `Enter`.

**Step 3** — Find the file `setup_jr_path.zsh` in the JR project folder in Finder. Drag it into the Terminal window and press `Enter`.

**Step 4** — You will see:
```
✅ PATH updated successfully.
```

**Step 5** — Open a new Terminal window (`Command + N`). You are ready.

**Step 6** — Type the name of any JR script and press `Enter`. On first run the environment will be set up automatically — this may take a minute. All subsequent runs are fast.

> You only need to run `setup_jr_path.zsh` once per machine.

---

## Quick Start for Administrators

> See the [Admin Manual](docs/admin_manual.docx) for full instructions. This is a summary.

**First-time setup** (requires internet):

```zsh
# 1. Clone the repository
git clone https://github.com/yourorg/jr-validated-environment.git
cd jr-validated-environment

# 2. Copy and edit the configuration file
cp config.zsh.template config.zsh
# Edit config.zsh to set your LOCAL_REPO path (Dropbox folder)

# 3. Build the local package repository and install the environment
export LOCAL_REPO="$HOME/Dropbox/my-cran-repo"
BUILD_REPO=true ./admin_install_R

export LOCAL_REPO="$HOME/Dropbox/my-python-repo"
./admin_install_Python --rebuild
```

**Subsequent setups** (no internet needed):

```zsh
./admin_install_R
./admin_install_Python
```

---

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                     Admin (once)                            │
│                                                             │
│  R_requirements.txt ──► admin_install_R ──► Dropbox repo    │
│  python_requirements.txt ► admin_install_Python             │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ (Dropbox sync)
┌─────────────────────────────────────────────────────────────┐
│                  Each User (automatic)                      │
│                                                             │
│  zsh wrapper ──► integrity check ──► rebuild if needed      │
│               ──► run R or Python script                    │
└─────────────────────────────────────────────────────────────┘
```

Package versions are pinned in `R_requirements.txt` and `python_requirements.txt`. Packages are downloaded once into a local Dropbox repository and never fetched from the internet again. Each user's environment is built automatically from this local repository on first run.

---

## Why Not Docker?

Docker is a legitimate alternative for running scripts in a controlled environment,
and the right choice depends on your team. Here is a concise comparison:

| | JR Validated Environment | Docker |
|---|---|---|
| Learning curve | Low — basic Terminal only | High — images, registries, Dockerfile |
| Audit transparency | High — plain text requirements files | Moderate — binary image requires tooling |
| macOS GUI output | Native, no configuration | Requires X11 or volume mapping |
| Resource usage | Minimal — no background processes | Heavy — Linux VM always running |
| Distribution | Dropbox sync | Registry + Docker Desktop install |
| Package updates | Edit one file, auto-propagated | Rebuild and redistribute entire image |
| Offline use | Yes | Requires local registry |
| Cross-platform | macOS only | macOS, Windows, Linux |
| System dependencies | R and Python packages only | Full OS-level control |

**Choose the JR Validated Environment if** your team is macOS-based, consists of
researchers or analysts rather than software engineers, and you want validation
evidence in plain text files that a Quality Manager can read directly without
additional tooling.

**Choose Docker instead if** your team includes Windows or Linux users, your scripts
depend on system-level libraries, or you are already working in a DevOps environment
with Docker expertise in the team.

The two approaches can also be combined — the `R_requirements.txt` and
`python_requirements.txt` files can serve as the source of truth for both the JR
local repository and a Dockerfile.

> For a detailed comparison including reproducibility, offline use, and regulatory
> considerations, see [docs/COMPARISON.md](docs/COMPARISON.md).


## Repository Structure

```
jr-validated-environment/
│
├── README.md                        ← this file
├── LICENSE
├── CHANGELOG.md
├── config.zsh.template              ← copy to config.zsh and edit
├── setup_path.zsh                   ← run once per machine to add to PATH
│
├── admin_install_R                  ← admin: set up R environment
├── admin_install_Python             ← admin: set up Python environment
├── admin_create_hash                ← admin: regenerate integrity file
├── generate_validate_R.zsh          ← admin: regenerate R validation script
├── generate_validate_Python.zsh     ← admin: regenerate Python validation script
│
├── validate_R_env                   ← auditors: validate R environment
├── validate_Python_env              ← auditors: validate Python environment
├── jrpy                             ← users: run any Python script in the environment
│
├── R/                               ← R analysis scripts
├── Python/                          ← Python analysis scripts
│
├── templates/
│   ├── jrR_template                 ← template for new R wrappers
│   └── jrPython_template            ← template for new Python wrappers
│
├── admin/
│   ├── R_requirements.txt           ← pinned R package versions
│   ├── R_base_requirements.txt      ← base R packages (verified, not installed)
│   ├── python_requirements.txt      ← pinned Python package versions
│   ├── python_base_requirements.txt ← standard library modules (verified)
│   ├── renv.lock                    ← renv lockfile (auto-generated)
│   ├── r_version.txt                ← required R version e.g. 4.5
│   ├── python_version.txt           ← required Python version e.g. 3.11.9
│   └── project_integrity.sha256     ← SHA256 integrity file
│
└── docs/
    └── admin_manual.docx            ← full administrator manual
```

---

## Validation Evidence

To generate a validation report suitable for an audit, run:

```zsh
# R environment
admin_validate_R_env

# Python environment
admin_validate_Python_env
```

Each command produces a report showing:
- R or Python version
- Every package version and the exact path it was loaded from
- Pass / fail status for each requirement

These scripts are auto-generated from the requirements files and can be re-generated at any time with `admin_generate_validate_R.zsh` or `admin_generate_validate_Python.zsh`.

---

## Adapting for Your Project

There are two ways to use the JR Validated Environment depending on your needs.

---

**Usage 1 — Install and configure for your project (recommended for most teams)**

Download the `.pkg` installer from the [Releases](https://github.com/yourorg/jr-validated-environment/releases)
page and follow the Admin Manual. After installation the admin performs these steps to configure
the environment for your project:

1. Edit `admin/R_requirements.txt` and `admin/python_requirements.txt` with the packages
   your scripts require.
2. Edit `admin/r_version.txt` and `admin/python_version.txt` with the R and Python versions
   you want to pin.
3. Set `LOCAL_REPO` in `config.zsh` to point to your shared Dropbox folder.
4. Run `admin_install_R --rebuild` and `admin_install_Python --rebuild` to build your own
   local package repository in Dropbox.
5. Add your R and Python scripts to the `R/` and `Python/` subfolders following the
   Admin Manual.
6. Create zsh wrappers for your scripts using the provided templates.
7. Run `admin_create_hash` to generate the project integrity file.
8. Run `generate_validate_R.zsh` and `generate_validate_Python.zsh` to generate the
   validation scripts.

Team members then run `setup_jr_path.zsh` once on their machine and the environment is ready.

---

**Usage 2 — Fork and extend the framework**

If you want to modify the architecture, contribute improvements, or significantly extend the
framework for your own purposes, fork this repository on GitHub, make your changes, and submit
a pull request if you would like your improvements included in the main project. Please read
the Contributing section before submitting.

---

## Regulatory Context

This framework is designed to support compliance with:

- **FDA 21 CFR Part 11** — electronic records and signatures
- **ISO 13485:2016** — quality management systems for medical devices
- **GAMP 5** — good automated manufacturing practice

The combination of pinned package versions, a controlled local repository, SHA256 integrity checking, and auto-generated validation reports provides the documentation trail typically required during a software audit or FDA submission.

> **Disclaimer:** This software is provided as a framework for building validated environments. It is the responsibility of each organisation to perform their own validation activities in accordance with applicable regulations. The authors make no warranties regarding the suitability of this software for any regulated purpose.

---

## Contributing

Contributions are welcome. Please open an issue before submitting a pull request so the proposed change can be discussed. All contributions must maintain compatibility with the validation framework — changes that weaken integrity checking or bypass the controlled package repository will not be accepted.

---

## Licence

Copyright 2026 JR Scripts

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for the full licence text.

---

## Support

For questions about adapting this framework for your project, open a GitHub issue.
