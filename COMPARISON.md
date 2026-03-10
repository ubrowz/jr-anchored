# JR Validated Environment vs Docker

A detailed comparison for teams evaluating their options for running validated
R and Python scripts in a medical device development context.

---

## Background

Both the JR Validated Environment and Docker solve the same core problem: ensuring
that scripts run in a controlled, reproducible environment where package versions
are pinned and the environment can be audited. They take fundamentally different
approaches, and the right choice depends on your team profile and technical context.

---

## Detailed Comparison

### Learning curve and team profile

The JR Validated Environment is designed for researchers and analysts who write
R and Python scripts and have basic Terminal familiarity. The admin needs to
understand zsh scripts and package management. End users need only drag a file
into Terminal once and then type script names.

Docker has a significant learning curve. Understanding images, containers, volumes,
Dockerfile syntax, registries, and networking is required before you can use it
productively. This is standard knowledge for DevOps engineers but is a substantial
barrier for a research-oriented medical device team.

---

### Audit transparency

In a regulated context, an auditor or Quality Manager needs to understand exactly
what software is running and why.

With the JR Validated Environment, the complete picture is in plain text files:
- `R_requirements.txt` and `python_requirements.txt` list every package and version
- `renv.lock` records the exact R package graph
- `validate_R_env` and `validate_Python_env` generate human-readable audit reports
- `project_integrity.sha256` provides tamper evidence for all scripts

A Docker image is a binary blob. Auditing its contents requires additional tooling
(`docker inspect`, `docker history`, scanning tools) and expertise that most
Quality teams do not have. A well-maintained Dockerfile is transparent, but the
built image itself is not.

---

### macOS GUI and file output

The JR Validated Environment runs scripts natively on macOS. File output lands
directly in the user's filesystem. GUI output (such as matplotlib graphics or
ggplot2 plots saved to PNG) works without any additional configuration.

Docker containers on macOS run inside a Linux VM via Docker Desktop. Getting GUI
output out of a container requires X11 forwarding or volume mounts. File output
requires explicit volume mapping. Neither is difficult for an experienced Docker
user, but both add friction for a research team.

---

### Resource usage

Docker Desktop on macOS runs a Linux virtual machine continuously in the background,
consuming significant RAM (typically 2–4 GB) and CPU even when no containers are
running. For a small startup where every team member's laptop matters, this overhead
is meaningful.

The JR Validated Environment has no background processes. It uses resources only
when a script is actively running.

---

### Distribution and updates

| Task | JR Validated Environment | Docker |
|---|---|---|
| Distribute to new team member | Dropbox sync + run setup_path.zsh once | Install Docker Desktop + pull image from registry |
| Update a single package | Edit requirements.txt, run admin_install_R --rebuild | Rebuild and push entire image |
| Team member picks up update | Automatic on next script run (hash check) | docker pull required |
| Works offline | Yes, after first Dropbox sync | Requires local registry or pre-pulled image |

---

### Reproducibility

A Docker image is immutable once built — the same image will always produce the
same result on any machine. This is Docker's strongest advantage.

The JR Validated Environment achieves high reproducibility through pinned package
versions, a controlled local repository, and SHA256 integrity checking. It relies
on discipline — not modifying files outside the admin workflow, not bypassing the
zsh wrappers — rather than technical enforcement. In practice, for a small team
working in a regulated environment where the Quality Manager reviews changes, this
discipline is maintainable.

---

### System-level dependencies

If your scripts depend on system libraries — for example GDAL for geospatial work,
specific C or Fortran libraries, or custom compiled tools — Docker handles these
cleanly by bundling them in the image. The JR Validated Environment manages only
R and Python packages, not system-level dependencies. If your scripts have such
requirements, Docker is the stronger choice.

---

### Cross-platform support

The JR Validated Environment is macOS-only. The zsh wrappers, renv paths, and
Python venv structure are all built around macOS conventions. Adapting it for
Windows would require significant rework.

Docker runs identically on macOS, Windows, and Linux. If your team is mixed-OS,
Docker is the more practical choice.

---

## Summary Table

| Dimension | JR Validated Environment | Docker |
|---|---|---|
| Learning curve | Low | High |
| Audit transparency | High — plain text files | Moderate — requires tooling |
| macOS GUI output | Native, no configuration | Requires X11 or volume setup |
| Resource usage | Minimal — no background processes | Heavy — Linux VM always running |
| Distribution | Dropbox sync | Registry + Docker Desktop |
| Package updates | Single file edit, auto-propagated | Full image rebuild and push |
| Offline use | Yes | Requires local registry |
| Reproducibility | High with admin discipline | Guaranteed — immutable image |
| Cross-platform | macOS only | macOS, Windows, Linux |
| System dependencies | Not supported | Fully supported |
| Target team profile | Research / analyst teams | DevOps-experienced teams |

---

## When to choose the JR Validated Environment

- Your team is macOS-based
- Your team consists of researchers or analysts rather than software engineers
- You want validation evidence in plain text that a Quality Manager can read directly
- You want minimal overhead on team members' machines
- Your scripts have no system-level dependencies beyond R and Python packages
- You want Dropbox-based distribution without managing a container registry

## When to choose Docker instead

- Your team includes Windows or Linux users
- You need guaranteed bit-for-bit reproducibility enforced at the OS level
- Your scripts depend on system libraries or compiled tools
- You are already working in a DevOps or cloud-native environment
- You have Docker expertise in the team and want to leverage it

---

## Can they be combined?

Yes. Some teams use both: the JR Validated Environment for day-to-day interactive
analysis on individual Macs, and Docker for automated pipeline runs in CI/CD or
cloud environments. The `R_requirements.txt` and `python_requirements.txt` files
can serve as the source of truth for both — the same pinned versions that go into
the JR local repo can also be used in a Dockerfile.

---

*See the README for a condensed version of this comparison.*
