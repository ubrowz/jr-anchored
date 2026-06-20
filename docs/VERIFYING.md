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
| ℹ️ **Release signature not verified here** | Git unavailable or signing not configured |

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
ssh-keygen -lf admin/allowed_signers
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
