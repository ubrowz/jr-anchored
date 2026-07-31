# Verifying the Authenticity of a JR Anchored Release

Every JR Anchored release is published as a **cryptographically signed Git tag**.
This lets you confirm that the code you cloned is a genuine, unmodified release
from the maintainer — not a tampered copy or a look-alike repository.

You normally do **not** need to do anything: the administrator's update flow
verifies the signature automatically and refuses to apply an unverified update.
This document is for administrators (or auditors) who want to verify by hand.

---

## What gets verified

- **Authenticity** — the release tag was signed with the maintainer's private
  key. The matching public key is pinned in [`admin/allowed_signers`](../admin/allowed_signers),
  and its fingerprint is published at **www.dwylup.com** so it has a trust root
  independent of GitHub.
- **Integrity** — the signed tag commits the exact tree state of the release.
  Any later change to a tracked file is additionally caught by the project
  integrity manifest (`admin/project_integrity.sha256`), which `jrrun` checks
  before every run.

---

## R and Python packages

The release signature covers **this repository** — scripts, wrappers,
configuration. The R and Python packages themselves are separate artifacts,
downloaded when an administrator builds the local package repository.

Since v4.10.0 they come from **https://www.dwylup.com/packages** first, with
CRAN as the fallback. CRAN serves only the current binary of each package, so a
pinned version disappears once the package is patched and a fresh install then
fails; the JR-hosted repository keeps the pinned versions frozen.

### What the validation actually claims

**The OQ evidence for a release is produced against exactly the package files
published in the JR repository.** For v4.10.0 all 193 published files were
verified byte-identical to the repository the OQ suite ran against. The
validated state and the published repository are the same artifacts.

That is the claim worth making, and it is the one a quality system needs: the
817 OQ test cases demonstrate that *these* package binaries, with these pinned
versions, produce the expected numerical results for known inputs. Whether
those bytes also match CRAN's current offering is incidental — CRAN is where
they originally came from, not the reference the validation is measured against.

Packages are unmodified upstream artifacts; nothing is rebuilt or patched.

### What is not yet covered

The published repository is a **live server**, and the OQ evidence describes a
snapshot of it. This release ships no mechanism that would detect the published
files later diverging from the validated state — through a bad upload, an
accident, or a compromise.

`admin/project_integrity.sha256` provides exactly that assurance for scripts,
and `jrrun` checks it before every run. The equivalent for packages is planned:
a committed, tag-signed manifest of the pinned package hashes, checked after
download. Until then:

- `admin/r_package_hashes.sha256` records a SHA-256 for every package file and
  `bin/jr_verify_packages` checks the shared repository against it before every
  install. That protects your own Dropbox or SMB copy from a later swap.
- It is generated **per machine** at build time and is not committed, so on a
  *first* build there is nothing to compare against — the hashes recorded are
  those of whatever was downloaded.

If your quality system requires packages traceable to a signed manifest today,
build the repository once on a trusted machine and distribute that copy; the
per-machine manifest protects it from that point on. Setting
`JR_PACKAGE_REPO=""` installs from CRAN alone, but note that this reintroduces
the failure the JR repository exists to remove, and CRAN is not a signed source
either.

Set `JR_PACKAGE_REPO` to override the source, or to `""` to opt out entirely.

---

## Automatic verification (default)

`admin_update` and `admin_setup` call `bin/jr_verify_release` for you:

- **Valid signature** → the update proceeds.
- **Invalid signature** → the update is **blocked**; the tampered code is never
  applied.
- **Signing not yet configured / Git not installed** → an advisory note is shown
  and the flow continues (verification is simply unavailable on that machine).

The GUI shows the result as a small status line in the sidebar:

| Banner | Meaning |
|---|---|
| ✅ **Verified release vX.Y.Z** | Signature valid — genuine release |
| ⛔ **Signature INVALID — do not use** | Tag signature failed — stop and re-clone |
| 🧪 **Development checkout (unsigned)** | Not at a release tag |
| 🔒 **Verified by your administrator on update** | Git unavailable on this machine (e.g. an end-user GUI) — the administrator's verified update/setup is the trust gate |

---

## Manual verification

On any machine with Git:

```bash
cd jr-anchored
bin/jr_verify_release            # verifies the current checkout (HEAD)
bin/jr_verify_release origin/release   # verifies the latest fetched release
```

Or with plain Git:

```bash
TAG=$(git describe --tags --abbrev=0)
git -c gpg.ssh.allowedSignersFile=admin/allowed_signers verify-tag "$TAG"
```

### Anchor the key to the maintainer (defeats a fake repository)

A signature only proves the tag was signed by *whatever key is in this clone*.
To prove it was signed by the genuine maintainer, confirm the pinned key matches
the fingerprint published on the website:

```bash
grep -v '^#' admin/allowed_signers | awk '{print $(NF-1), $NF}' | ssh-keygen -lf -
```

Compare the printed `SHA256:...` fingerprint with the one at
**www.dwylup.com** (Verifying / Security page). If they match, the release is
authentic. If they differ, do not trust the copy.

---

## For maintainers — signing a release

One-time setup:

```bash
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub   # your signing key
```

Add the corresponding public key to `admin/allowed_signers` (replacing the
PLACEHOLDER line) and publish its fingerprint on www.dwylup.com.

Per release — sign the tag:

```bash
git tag -s vX.Y.Z -m "JR Anchored vX.Y.Z"
git push origin vX.Y.Z
```

`git tag -s` produces a signed tag; everything above then verifies it.
