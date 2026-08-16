---
status: Draft
date: 2026-08-16
deciders:
  - aaronsb
  - claude
related:
  - ADR-200
---

# ADR-300: One conduit publishes every AUR package

## Context

Thirteen AUR packages are maintained across nine repositories. An audit on
2026-08-16 found that none of them published automatically. Every AUR push was
manual, and each repository had grown its own approach to doing it:

| Repository | PKGBUILD | AUR push mechanism |
|---|---|---|
| `playtimed` | `./PKGBUILD` | none |
| `clicue` | `./packaging/aur/PKGBUILD` | `make publish-aur`, plus `make repo` |
| `mmaid-go` | `./PKGBUILD` | `make aur`, `make aur-push` |
| `markdown-mixed-media` | `./PKGBUILD` | `make aur` → `scripts/update-aur.sh` |
| `obsbot-camera-control` | `./PKGBUILD` | none |
| `fake-battery-nut` | `./PKGBUILD` | none |
| `bosectl-qt` | `./PKGBUILD`, `./PKGBUILD-git` | `make aur-publish` |
| `yay-friend` | none — lives only in the AUR | none |
| `arch-repo` | `PKGBUILDs/*/PKGBUILD` | automated ([[ADR-200]]) |

Four different names for the same operation, three repositories with no
mechanism at all, and one package whose recipe exists nowhere but the AUR.

The cost of this is not theoretical. `mlterm-fb` sat flagged out-of-date on the
AUR at 3.9.4 while upstream had shipped 3.9.5. Bringing it into `arch-repo` and
running it through CI for the first time also surfaced three defects it had been
shipping: a `license=('BSD')` field that is not an SPDX identifier, an
undeclared `libx11` dependency from a helper binary that cannot work on the
framebuffer this package targets, and a `package()` step whose licence install
guessed three wrong filenames and ended in `|| true`, so the package shipped
with no licence file at all. Hand publishing had never run a linter.

`clicue` additionally publishes its own single-package pacman repository, with
its GitHub release serving `[clicue]` (its ADR-401). That is a second
distribution channel overlapping the `[aaronsb]` repository this project already
serves. Its user population is one person, who is not currently using it.

## Decision

`arch-repo` is the only path to the AUR and to the `[aaronsb]` pacman
repository, for every package.

Each source repository keeps its PKGBUILD at `./PKGBUILD` and tags releases
`vX.Y.Z`. `arch-repo` watches for new tags, pulls the PKGBUILD at that tag,
builds it, lints it, signs it, and publishes to both channels. Source
repositories need no CI, no AUR credential, and no packaging automation of their
own.

Consequently:

- The hand-rolled AUR targets in `clicue`, `mmaid-go`, `markdown-mixed-media`
  and `bosectl-qt` are removed, along with the scripts behind them. Two writers
  to one AUR ref is how a PKGBUILD and its `.SRCINFO` drift apart.
- `clicue`'s PKGBUILD moves to the repository root, and its `[clicue]` pacman
  repository folds into `[aaronsb]`. Its ADR-401 is superseded by this one.
- `yay-friend` gains a real PKGBUILD at `v0.6.0`, alongside the existing
  `yay-friend-git`.

Packaging stays next to source rather than moving into `arch-repo`, so a change
that breaks the build travels in the same commit as the PKGBUILD that must
adapt to it.

## Consequences

### Positive

- Every package is linted, built in a clean container, and signed before it
  reaches anyone. Three defects in the first package onboarded suggest this is
  the substantive change, not the automation.
- One AUR credential, in one repository, rather than eight.
- One pacman repository carrying everything, so a machine adds one stanza.
- A release is a tag. Nothing else is a release action.

### Negative

- Polling latency. A tag is picked up on the next scheduled run rather than
  immediately, which an hourly cron makes about thirty minutes on average.
- `arch-repo` becomes a single point of failure for publishing. Its `BUMP_PAT`
  expiring stops every package at once, which is why that failure is loud rather
  than degraded.
- Existing `[clicue]` users must edit `pacman.conf`. There is one.
- Every bump rebuilds every package, because `publish` reassembles the whole
  repository database. At thirteen packages including DKMS and Qt builds this
  becomes the dominant cost, and will need `publish` to merge into the existing
  database rather than recreate it.

### Neutral

- VCS packages (`yay-friend-git`, `bosectl-qt-git`) cannot be version-watched;
  their `pkgver()` computes from commit count at build time. They need a
  periodic rebuild trigger rather than a version comparison, which the [[ADR-200]]
  contract accommodates by comparing HEAD's sha rather than a version.
- `bosectl-qt` ships two PKGBUILDs from one repository, so "the PKGBUILD at the
  root" is a convention with one documented exception rather than an invariant.

## Alternatives Considered

- **Move every PKGBUILD into `arch-repo`.** Rejected: it separates packaging
  from the source it packages, so a build-breaking change and the PKGBUILD fix
  it requires land in different repositories at different times.
- **A standard release workflow installed in all eight repositories.** Rejected:
  eight copies of the same workflow to maintain, and the AUR signing key
  distributed to eight repositories' secrets rather than held in one.
- **Source repositories dispatch to `arch-repo` on tag.** Removes the polling
  latency, at the cost of a credential and a workflow in every repository —
  the thing the previous alternative was rejected for. Worth revisiting if the
  latency turns out to matter.
- **Leave `clicue` self-publishing.** Rejected: it is the drift being removed,
  and preserving one exception preserves the reason the audit was needed.
