---
status: Draft
date: 2026-08-16
deciders:
  - aaronsb
  - claude
related:
  - ADR-100
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

What a source repository provides in exchange is [[ADR-100]]'s contract: a
recipe at a fixed location on the default branch, and nothing that publishes.
`arch-repo` watches, builds, lints, signs, and pushes to both channels. Source
repositories need no CI, no AUR credential, and no packaging automation of
their own.

The recipe comes from the **default branch**, and only the version and checksum
come from the tag. This looked like a shortcut when first written here and is
not: a PKGBUILD cannot carry the checksum of the tarball its own tag produces,
because the hash does not exist until the tag does. At `v0.5.3`, `playtimed`'s
PKGBUILD still read `pkgver=0.5.2` with the 0.5.2 hash — and the `make aur`
target every one of these repositories grew exists precisely to go back and fix
that after tagging. Reading the branch for the recipe and the tag for the two
moving values removes the circularity instead of automating a walk around it.

It follows that a source repository's own `pkgver` and `sha256sums` stop
mattering, and [[ADR-100]] extends that to `pkgrel` and `.SRCINFO`: `arch-repo`
overwrites all four, so their drifting stale — which is what they have all been
doing — no longer reaches anyone.

Every repository that publishes to the AUR itself gives that up. Two writers to
one AUR ref is how a PKGBUILD and its `.SRCINFO` drift apart, and the conduit is
worth nothing if a second path stays open beside it.

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
- Releasing is cutting a release. There is no second action afterwards, and a
  packaging fix needs no release at all — [[ADR-100]] and [[ADR-200]] make it a
  `pkgrel` bump.

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
