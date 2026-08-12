# arch-repo

A signed pacman repository, built by CI, for packages this fleet needs but
shouldn't take from the AUR.

## Why

The June–July 2026 "Atomic Arch" campaign adopted ~1,500 orphaned AUR packages
and modified their PKGBUILDs to pull a credential stealer. Arch disabled AUR
package adoption on 2026-07-30. The lasting lesson isn't about those specific
packages: `yay` re-fetches a PKGBUILD from the AUR on every upgrade, so any
package you install is a standing grant to whoever holds that AUR account.

This repository inverts that. Recipes live here and change only by commit. What
they fetch is pinned by hash, and — where upstream publishes signatures — that
hash is re-derived from the upstream signature at build time rather than taken
on trust.

## Using it

Add to `/etc/pacman.conf`, above the standard repositories:

```ini
[aaronsb]
Server = https://github.com/aaronsb/arch-repo/releases/latest/download
SigLevel = Required TrustedOnly
```

Import and locally sign the repository key:

```bash
sudo pacman-key --recv-keys <REPO_KEY_FINGERPRINT>
sudo pacman-key --lsign-key <REPO_KEY_FINGERPRINT>
sudo pacman -Sy
```

## Packages

| Package | Upstream | Provenance |
|---------|----------|------------|
| `ya-claude` | Anthropic's official Claude Desktop `.deb` | GPG-verified against Anthropic's signed apt index at build time |

### ya-claude

Repackages the official Debian build. It is not a fork and carries no patched
code — the payload is Anthropic's, unmodified.

Its build refuses to proceed unless the whole chain holds:

1. The signing key committed at `PKGBUILDs/ya-claude/anthropic-release-signing.key`
   has fingerprint `31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE`.
2. `InRelease` carries a good signature from that key.
3. `Packages` matches the hash `InRelease` signs for it.
4. The `.deb` hash pinned in the PKGBUILD equals the one that signed index
   records for this version.

Step 4 is the one that matters and the one no AUR equivalent performs. A pinned
hash alone proves only that a payload hasn't changed since the packager wrote
the number down — it says nothing about whether that number was ever Anthropic's.
Substituting a tampered `.deb` *and* its matching hash passes `makepkg`'s own
validation and fails here.

Differences from upstream's Debian package, all forced by Arch's layout and each
verified against the resolver in `resources/app.asar`:

- `/usr/bin/virtiofsd` → `/usr/lib/virtiofsd`. The app searches `/usr/libexec`
  then `/usr/bin`, falling back to its bundled copy only on Ubuntu 22.x, so on
  Arch the system binary is the only one ever reached.
- `/usr/share/edk2/OVMF_{CODE,VARS}_4M.fd` → the `x64/` firmware. The app opens
  Debian's names and derives the VARS path from the CODE path by substring
  replacement, so both links are needed.
- The `.deb`'s maintainer scripts are discarded. They register an apt repository
  and install an AppArmor profile gated on Ubuntu's userns restriction.
- `libgcc` + `libstdc++` rather than `gcc-libs`, which is now a metapackage that
  would drag in `libasan`, `libtsan`, `libubsan`, `libgfortran` and `libquadmath`.

Computer Use is not included. Upstream doesn't ship it on Linux yet, and the
third-party patch that adds it means running a modified `app.asar` — a different
trust decision, deliberately kept out of this package.

## CI

`update.yml` polls the signed index daily and opens a PR when upstream moves;
the version and hash it writes are read only after the signature verifies.
`build.yml` builds in an `archlinux` container, gates on `namcap`, then signs
and publishes the repository as a rolling GitHub Release.

CI is part of the trust path — worth stating plainly. It's partly self-limiting:
verification happens inside the build, so a compromised runner can't swap the
payload without also forging Anthropic's signature. It could still tamper with
the output, which is what the repository signing key addresses.
