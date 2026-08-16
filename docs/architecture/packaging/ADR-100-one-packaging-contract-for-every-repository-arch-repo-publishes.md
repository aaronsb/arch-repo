---
status: Accepted
date: 2026-08-16
deciders:
  - aaronsb
  - claude
related:
  - ADR-200
  - ADR-300
---

# ADR-100: One packaging contract for every repository arch-repo publishes

## Context

Six source repositories independently grew their own AUR publisher — two
Makefile targets, three shell scripts, one zsh script — and converged on the
same procedure without ever being designed together: verify a version, run
`updpkgsums`, regenerate `.SRCINFO`, clone the AUR repository, commit, push.

Moving that procedure into `arch-repo` removes the duplicated code. It does not
remove the part that recurs with every new project: working out what
`arch-repo` will need. Each repository packaged so far answered that
differently, and the answers are not interchangeable — a recipe under
`packaging/aur/`, a recipe held only in the AUR git repository with no
version-controlled home, a `pkgver()` published with its template placeholder
still in it.

At least one of those was reasoned rather than guessed. `clicue`'s PKGBUILD
carries `sha256sums=SKIP` under a comment observing that a committed sum would
be circular, since the file ships inside the tarball it would checksum. That is
the circularity [[ADR-300]] identifies, reached independently, and answered by
keeping the sum out of version control rather than by taking the recipe from
the branch and the hash from the tag. Both answers are defensible; `arch-repo`
can implement only one.

A contract also has to say what it means by a version. `arch-repo` currently
gets that wrong wherever a repository has published no GitHub release: it falls
back to the raw tag list, which carries pre-releases, and `sort -V` prefers
them.

```
$ printf 'v1.2.0\nv1.2.0-rc1\n' | sort -V | tail -1
v1.2.0-rc1
```

## Decision

Every repository that publishes through `arch-repo` satisfies one contract, and
that contract belongs to the repository rather than to `arch-repo`. Software
this maintainer does not own is not an exception: `arch-repo` stands in as the
source repository and satisfies the contract on that package's behalf.

The contract's clauses are documented at
[`docs/packaging-contract.md`](../../packaging-contract.md), which is read when
starting a project rather than when deciding one. What is decided here:

- **The repository holds the recipe**, at a fixed location on the default
  branch. The location is not configurable per repository.
- **Two package shapes exist** — a versioned package and a VCS companion — and
  a repository declares which it publishes by which recipe it carries.
- **`arch-repo` owns `pkgver`, `pkgrel`, `sha256sums` and `.SRCINFO`.** A
  repository may declare them; it does not maintain them, and they are
  overwritten before anything is published.
- **A version is a published release, not a tag.** Where a version can only be
  read from tags, the list is filtered to release tags before it is sorted.
- **No repository talks to `aur@aur.archlinux.org`.** Publishing is
  `arch-repo`'s, and having it in two places means two writers racing for one
  AUR repository.
- **Republishing unchanged software is a `pkgrel` bump in `arch-repo`** — not a
  new tag, and not a patch release of software that did not change.

The contract is prescriptive for repositories that do not exist yet. Bringing
existing ones into conformance is ordinary work, tracked as ordinary work, and
is not part of this decision.

## Consequences

### Positive

- Packaging a new project is following a written contract rather than
  reconstructing one from whichever previous project got it right.
- Six publishers are deleted rather than maintained. Their bugs go with them.
- The recipe living on the default branch while the version comes from the tag
  ([[ADR-300]]) means conformance work ships as `pkgrel` bumps. A repository can
  be brought into the contract without releasing software that did not change.
- Whether the payload is this maintainer's software or a vendor's printer driver
  stops being a structural distinction and becomes one field. `arch-repo` never
  learns Rust, Go, npm or DKMS; each recipe already knows.

### Negative

- Repositories that solved publishing their own way have to give it up, and at
  least one of those solutions works today.
- The contract is enforced by review, like the watcher contract in [[ADR-200]].
  A repository that puts its recipe somewhere else is never onboarded rather
  than reported.
- Asking every repository for a clean-chroot build target is new per-repository
  surface, repeated in each of them.

### Neutral

- The publish half of `arch-repo` already works this way: the `aur` job copies a
  package directory, regenerates `.SRCINFO`, and pushes only when the staged diff
  is non-empty. It has never asked what the payload was. What this contract
  changes is upstream of that, in discovery.
- VCS packages stop being the hard case. With detection on recipe content rather
  than version ([[ADR-200]]), a VCS package needs no version discovery at all —
  a changed recipe is the only reason to publish one.
- Trust stays per-package. A package whose upstream signs its releases can verify
  a chain before reporting a version; one whose upstream signs nothing cannot,
  and holds its pull request for a human. That difference is about what upstream
  publishes, not about who wrote the software, so no amount of unification
  removes it.

## Alternatives Considered

- **Leave each repository publishing itself and keep `arch-repo` for the pacman
  repository only.** Rejected as the status quo whose cost prompted this: one
  implementation of the same procedure per project, forever.
- **Teach `arch-repo` to find a recipe wherever a repository put it** — a
  configurable path per package. Rejected because it makes the tool absorb the
  variance instead of removing it, and the next repository invents a location
  nobody has seen yet.
- **Have `arch-repo` drive each repository's own build** — invoke a declared
  entrypoint and package the artifact it emits. Rejected: it needs a second
  contract for what that entrypoint is called and what it produces, and it moves
  the build outside `makepkg`'s clean chroot, which is what namcap and the
  reproducibility claim rest on. The PKGBUILD is already a standard build
  process.
- **A central manifest in `arch-repo` listing every package and its rebuild
  state.** Rejected for the reason [[ADR-200]] rejected a central build matrix:
  a written-down list is a second source of truth that drifts from the tree.
  `pkgrel` in the recipe already carries the state a rebuild trigger would.
