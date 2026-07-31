# Platform Support — JR Anchored

---

## Supported Platforms

| Platform | Status | Notes |
|---|---|---|
| macOS 13 Ventura and later (Apple Silicon) | ✅ Supported | Primary development platform |
| macOS 13 Ventura and later (Intel) | ✅ Supported | Requires an Intel-built package repo — see below |
| Windows 10 / 11 | ✅ Supported | Since v2.0.0, via Git Bash |
| macOS 12 or earlier | ⚠️ Not tested | May work but is not validated |
| Linux | ❌ Not supported | See below |

---

## One platform per environment

**The administrator and every end user must be on the same operating system.**
JR Anchored does not support mixed-OS teams.

This follows from how the environment gets its packages. The administrator
builds a local package repository once and shares it (via Dropbox or an SMB
network share); everyone else installs from that copy and never downloads from
the internet at runtime. R package **binaries are platform-specific**, so a
repository built on macOS contains only macOS binaries and cannot serve a
Windows client — or the reverse.

In practice:

- A macOS admin serves macOS users.
- A Windows admin serves Windows users.
- A team with both needs **two administrators and two separate repositories**,
  maintained independently.

The same rule applies one level down, to CPU architecture on macOS: a repo
built on Apple Silicon cannot serve Intel Macs, or the reverse. A mixed
Apple Silicon / Intel team also needs two repositories.

> If your team is genuinely mixed-OS and you do not want to maintain parallel
> environments, Docker is the more practical choice. See
> [COMPARISON.md](COMPARISON.md).

---

## Pinned toolchain

Both platforms pin the same versions, recorded in the repository:

| Component | Pin file | Current |
|---|---|---|
| R | `admin/r_version.txt` | 4.6 |
| Python | `admin/python_version.txt` | 3.11.9 |

---

## macOS notes

**Binary flavour.** The R binary type is `mac.binary.<flavour>`, where the
flavour is supplied by the `admin_install_R` wrapper as `R_MACOS_PLATFORM`.
CRAN renames the flavour every few R releases, so it tracks the R pin:

| R version | macOS arm64 flavour |
|---|---|
| 4.5 | `big-sur-arm64` |
| 4.6 | `sonoma-arm64` |

Intel Macs use the `big-sur-x86_64` flavour. Because miniCRAN does not
reliably fetch every flavour, `admin/R/admin_R_install.R` downloads those
binaries from CRAN directly.

**Xcode Command Line Tools** — administrator only, for git and the compiler
toolchain some R packages need while the repository is being built:

```zsh
xcode-select --install
```

End users do not need them; they install from the pre-built repository.

---

## Windows notes

Supported since v2.0.0. The shell scripts run under **Git Bash**, which ships
with Git for Windows — install it and select *Git from the command line and
also from 3rd-party software* during setup. `guide_install.html` walks through
every installer screen.

The R binary type is `win.binary`, and those binaries are downloaded from CRAN
directly rather than via miniCRAN, for the same reason as the macOS flavours
above.

Windows end users who only need the GUI do not need Git for Windows at all —
the administrator exports a pre-configured app bundle for them.

---

## Shared storage

The package repository reaches the team by either:

- **SMB network share** — built into Windows and macOS, no extra software, no
  account, no storage limit. Requires the host to be on and reachable.
- **Dropbox** — syncs a local copy to each machine, so it works offline once
  synced, at the cost of an account and quota.

Neither is required by the software itself: setup records whichever path you
give it.

---

## Linux — Not Supported

The local R repository is built from platform-specific binaries for macOS and
Windows only, and the Python distribution model assumes those two platforms.
Linux support would require:

- Rebuilding the local R repo with Linux binaries, or accepting source-only
  installs (slower, and needs a compiler toolchain on every machine)
- Handling Linux platform strings in the renv library path
- A Linux-appropriate Python distribution method

Contributions are welcome provided they do not degrade macOS or Windows. See
[CONTRIBUTING.md](../CONTRIBUTING.md).

---

## Docker

Docker is deliberately not a goal for this project. See
[COMPARISON.md](COMPARISON.md) for why a native validated environment is
preferred over a container in medical device development — and for the one
case (a mixed-OS team) where the opposite holds.
