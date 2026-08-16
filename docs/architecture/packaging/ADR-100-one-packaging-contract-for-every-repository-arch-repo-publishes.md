---
status: Draft
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

Thirteen packages carry this maintainer's name on the AUR. Nine reach it, or
will, through `arch-repo`. The other four do not, and the reasons they do not
are all different.

Six of the source repositories grew their own AUR publisher, independently, at
different times:

| Repository | Publisher |
|---|---|
| `bosectl-qt` | `Makefile` |
| `mmaid-go` | `Makefile` |
| `clicue` | `packaging/publish-aur.zsh` |
| `fake-battery-nut` | `publish-aur.sh` |
| `markdown-mixed-media` | `scripts/update-aur.sh` |
| `obsbot-camera-control` | `publish-aur.sh`, plus instructions in `.claude/claude.md` and a way |

They converged on the same shape without ever being designed together: verify a
version, run `updpkgsums`, regenerate `.SRCINFO`, clone the AUR repository,
commit, push. Six implementations of one procedure, each with its own bugs, each
needing to be remembered when the next project is packaged.

Moving the procedure into `arch-repo` removes the duplicated code. It does not
remove working out, per project, what `arch-repo` will need. Three of the four
uncovered packages are uncovered for that reason, and each found a different way
to be unpackageable:

| Package | Why it is outside |
|---|---|
| `clicue` | Recipe at `packaging/aur/PKGBUILD`, not the repository root. Also runs a second, complete release system: its own `[clicue]` pacman repository published to a GitHub release. |
| `yay-friend-git` | No PKGBUILD anywhere in the source repository. The recipe exists only in the AUR git repository, with no version-controlled home. |
| `bosectl-qt-git` | Published as `0.3.0.r0.g0000000-1`. `pkgver()` is correct and would emit a real `r<count>.g<hash>`, but the committed literal and the published `.SRCINFO` both carry the template placeholder. The base version `0.3.0` is also hardcoded inside `pkgver()`, so it will keep saying `0.3.0.rN` after `v0.4.0` is tagged. |
| `brother-hl-l3295cdw` | Not this maintainer's software. There is no source repository to hold a recipe. |

Only the last of those is a genuine difference in kind. The first three are a
repository having guessed differently, in the absence of anything to guess
against.

`clicue` is the clearest case, because it did not guess badly — it reasoned. Its
PKGBUILD carries `sha256sums=SKIP` under a comment explaining that a committed
sum would be circular, since the file ships inside the tarball it would
checksum. That is the same circularity [[ADR-300]] identifies, diagnosed
independently and correctly, and answered by keeping the sum out of version
control instead of by taking the recipe from the branch and the hash from the
tag. Two good answers to one question is what an unwritten contract produces.

A spec has to say what it means by a version, and `arch-repo` currently gets
that wrong in one place. `github_latest` asks for `releases/latest`, which
GitHub filters to non-prerelease, non-draft. When a repository has cut no
releases it falls back to the tag list, which is not filtered at all — and
`sort -V` prefers the pre-release:

```
$ printf 'v1.2.0\nv1.2.0-rc1\n' | sort -V | tail -1
v1.2.0-rc1
```

`obsbot-camera-control` and `yay-friend` both return 404 from `releases/latest`
and sit on that fallback today.

## Decision

Every repository that ships a package through `arch-repo` satisfies one
contract, and the contract belongs to the repository rather than to `arch-repo`.
Software this maintainer does not own is not an exception to it: `arch-repo`
stands in as the source repository and satisfies the same contract on that
package's behalf.

### What the repository provides

At the root of the default branch:

| File | When | What it is |
|---|---|---|
| `PKGBUILD` | versioned package | The recipe. `pkgver`, `pkgrel` and `sha256sums` are placeholders. |
| `PKGBUILD-git` | `-git` companion package | The VCS recipe. No fixed version at all. |
| files either recipe names | as needed | `.install` hooks, bundled licences |

Nothing else, and in particular nothing that talks to `aur@aur.archlinux.org`.

### The two shapes

**`my-app`** — versioned. The version comes from a published GitHub **release**,
not from a bare tag. `source=` names an artifact that release carries. For most
projects that artifact is GitHub's generated source tarball
(`$url/archive/v$pkgver.tar.gz`) and cutting the release is sufficient; where the
package ships something built instead, `make release` produces it and the release
carries it as an asset.

A release is required rather than a tag because GitHub already excludes drafts
and pre-releases from `releases/latest`, and a tag list has no such notion.
`obsbot-camera-control` and `yay-friend` tag without releasing today; that is a
repository fix. The tag fallback stays, filtered to release-shaped tags, for
upstreams this contract has no authority over.

**`my-app-git`** — VCS. `source=("$_pkgname::git+$url.git")` with
`sha256sums=('SKIP')`. There is no version to watch, and `pkgver()` derives one
at build time without hardcoding a base:

```sh
pkgver() {
    cd "$_pkgname"
    git describe --long --tags --abbrev=7 | sed 's/^v//; s/\([^-]*-g\)/r\1/; s/-/./g'
}
```

The obligation a `-git` package places on the repository is that the default
branch builds at HEAD, always. The obligation a versioned package places on it
is that a release tag carries artifacts the recipe can consume.

### The make pattern

Three targets, named the same way in every repository:

| Target | Produces | Read by |
|---|---|---|
| `make check` | nothing; verifies | the repository's own CI, before a tag |
| `make package` | the package, built from `./PKGBUILD` in a clean chroot, then namcap'd | a human, before a tag |
| `make release` | the artifacts a tag must carry; frequently empty | the recipe's `source=` |

`make check` is where the repository's internal version consistency is asserted
— that the tag about to be cut agrees with `Cargo.toml`, `package.json` or the
go module. `clicue` already performs that check and it survives unchanged; what
changes is which two values it compares, because under this contract the
committed `pkgver` is not one of them.

`make package` is the pre-tag dry run of what `arch-repo` will do: a recipe that
would fail in a bump pull request fails on the desk instead.

There is no `make aur`, no `make publish-aur`, no `publish-aur.sh`.

### What arch-repo owns

The repository declares these fields and does not maintain them. `arch-repo`
overwrites all of them, so their being stale in the source repository — which is
what they have all been doing — reaches nobody:

| Field | Where it really comes from |
|---|---|
| `pkgver` | the newest release tag |
| `pkgrel` | `arch-repo`'s count of how many times it has packaged that release |
| `sha256sums` | computed from the tag's artifact |
| `.SRCINFO` | regenerated at publish from the rendered recipe |

Where the version is read from the tag list rather than from a release, the list
is filtered to release tags before it is sorted.

### Republishing without a change

Bumping `pkgrel` in `arch-repo`'s copy of a recipe and pushing to `main` is the
whole mechanism. It is stable: the watcher renders the upstream recipe carrying
the committed `pkgrel`, finds no difference, and leaves it alone. Verified
against `playtimed`.

This is deliberately not a manifest. A separate file recording which packages
want rebuilding would say what the PKGBUILD already says, in a second place that
can disagree with the first.

### What bringing a repository into conformance costs

Almost nothing a user sees, because the recipe comes from the default branch and
that is where all of it happens. Moving a PKGBUILD to the root, adding the three
make targets, correcting a `pkgver()`, dropping a publisher — none of it changes
a byte of the software or needs a new tag. Each lands as `pkgrel` advancing:
`1.2.0-1` to `1.2.0-2`, and again if a second pass is needed, which is what
detection on recipe content in [[ADR-200]] is for.

A new tag is needed only when the contents of the tarball must change — a
package adopting the built-artifact shape, whose release has to start carrying
an asset, or a build that comes to need a file the last tag does not contain.
None of the thirteen packages is in that position today.

The alternative is cutting a patch release per packaging fix, which asks a
project to release software that did not change and spends a version number on
something a reader of the changelog cannot act on. `pkgrel` resets to 1 at the
next genuine release, so a package that reaches `1.2.0-4` during normalisation
carries no trace of it afterwards.

## Consequences

### Positive

- Packaging a new project is following a written contract rather than
  reconstructing one from the last project that got it right.
- Six publishers are deleted rather than maintained. Their bugs go with them.
- `clicue`'s circularity argument is answered rather than worked around, and its
  `sha256sums=SKIP` becomes a real hash without the tagging order changing.
- The distinction that looked fundamental — our software versus a printer driver
  — becomes one cell of configuration. `arch-repo` never learns Rust, Go, npm or
  DKMS; each recipe already knows.

### Negative

- Two repositories have to move before they conform, and `clicue` has to give
  up a working release system to do it.
- The contract is enforced by review, like the watcher contract above it. A
  repository that puts its PKGBUILD somewhere else is never onboarded rather
  than reported.
- `make package` asks every repository to carry a clean-chroot build target most
  of them did not have — new per-repository surface, and the same three lines in
  each.

### Neutral

- The publish half of `arch-repo` already satisfies this: the `aur` job copies a
  package directory, regenerates `.SRCINFO`, and pushes only when the staged diff
  is non-empty. It has never asked what the payload was. What this contract
  changes is upstream of that, in discovery.
- `-git` packages stop being the hard case. With detection on recipe content
  rather than version ([[ADR-200]]), a VCS package needs no version discovery at
  all — a changed recipe is the only reason to publish one.
- Trust stays per-package. `ya-claude` verifies a GPG chain before it will report
  a version; `mlterm-fb` has no upstream signatures and carries `.no-auto-merge`.
  That difference is about what upstream publishes, not about who wrote the
  software, so no amount of unification removes it.

## Alternatives Considered

- **Leave each repository publishing itself and keep `arch-repo` for the
  pacman repository only.** Rejected as the status quo whose cost prompted this:
  six implementations of one procedure, and a seventh to write for every new
  project.
- **Teach `arch-repo` to find a recipe wherever a repository put it** — a
  configurable path per package, so `clicue` keeps `packaging/aur/PKGBUILD`.
  Rejected because it makes the tool absorb the variance instead of removing it.
  A configurable path is a contract with one clause that is always negotiable,
  and the next repository invents a third location.
- **Have `arch-repo` drive each repository's own build** — invoke a declared
  entrypoint, package the artifact it emits. Rejected: it needs a second contract
  for what that entrypoint is called and what it produces, and it moves the build
  outside `makepkg`'s clean chroot, which is what namcap and the reproducibility
  claim currently rest on. The PKGBUILD is already the build process, and it is
  already standard.
- **A central manifest in `arch-repo` listing every package and its rebuild
  state.** Rejected for the reason [[ADR-200]] rejected a central build matrix:
  a written-down list is a second source of truth that drifts from the tree.
  `pkgrel` in the recipe already carries the state a rebuild trigger would.
