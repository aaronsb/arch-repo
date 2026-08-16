# Packaging a project through arch-repo

What a source repository provides so that `arch-repo` can build, lint, sign and
publish it to the AUR and the `[aaronsb]` pacman repository. The decision behind
this is [ADR-100](architecture/packaging/ADR-100-one-packaging-contract-for-every-repository-arch-repo-publishes.md);
this page is the contract itself, and [`example/`](example/) is a complete
repository laid out to it — copy from there rather than from the fragments
below, since CI reads it with the same helpers that read a real repository.

Read this once when starting a project. Nothing here is per-package configuration
— `arch-repo` looks in the same places in every repository.

## What the repository provides

At the root of the default branch:

| File | When | What it is |
|---|---|---|
| `PKGBUILD` | versioned package | The recipe. |
| `PKGBUILD-git` | VCS companion package | The VCS recipe. |
| whatever those name | as needed | `.install` hooks, bundled licences |

A repository may carry either recipe or both. Both publish, under their own AUR
names, from the same source.

Nothing else — and in particular, nothing that talks to
`aur@aur.archlinux.org`.

## The two shapes

### `my-app` — versioned

The version comes from a **published GitHub release**, not a bare tag. GitHub
excludes drafts and pre-releases from `releases/latest`; a tag list has no such
notion, and sorting one picks `v1.2.0-rc1` over `v1.2.0`.

`source=` names an artifact the release carries. For most projects that is
GitHub's generated source tarball and cutting the release is the whole job —
see [`example/PKGBUILD`](example/PKGBUILD).

Where the package ships something built instead, `make release` produces it, the
GitHub release carries it as an asset, and `source=` points at the asset URL.

### `my-app-git` — VCS

There is no version to watch. The recipe is published when the recipe changes
and at no other time. See [`example/PKGBUILD-git`](example/PKGBUILD-git).

Derive the base version from `git describe`. Hardcoding it —
`printf "0.3.0.r%s.g%s"` — leaves the package claiming `0.3.0` forever after
`v0.4.0` is tagged, and regenerate `.SRCINFO` from an evaluated `pkgver()`: a
placeholder like `0.3.0.r0.g0000000` names a commit that does not exist, and
that string is what `yay` and `paru` compare against.

The obligation a VCS package places on the repository is that the default branch
builds at HEAD, always.

## What arch-repo owns

Declare these so the recipe is valid on its own. Do not maintain them:
`arch-repo` overwrites all four before anything is published, so their being
stale costs nothing.

| Field | Where it really comes from |
|---|---|
| `pkgver` | the newest published release |
| `pkgrel` | `arch-repo`'s count of how many times it has packaged that release |
| `sha256sums` | computed from the release's artifact |
| `.SRCINFO` | regenerated at publish from the rendered recipe |

A PKGBUILD cannot carry the checksum of the tarball its own tag produces — the
hash does not exist until the tag does. This is why the recipe comes from the
default branch and only the version and checksum come from the release, and why
placeholder values are correct rather than sloppy.

## The make pattern

Three targets, named the same way in every repository — see
[`example/Makefile`](example/Makefile):

| Target | Produces | Read by |
|---|---|---|
| `make check` | nothing; verifies | the repository's own CI, before a release |
| `make package` | the package, built from `./PKGBUILD` in a clean chroot, then namcap'd | a human, before a release |
| `make release` | the artifacts a release must carry; frequently empty | the recipe's `source=` |

`make check` is where the repository's internal version consistency is asserted:
that the tag about to be cut agrees with `Cargo.toml`, `package.json`, or the go
module. The committed `pkgver` is not one of the values compared — `arch-repo`
owns it.

`make package` is the pre-tag dry run of what `arch-repo` will do. A recipe that
would fail in a bump pull request fails on the desk instead.

There is no `make aur`, no `make publish-aur`, no `publish-aur.sh`.

## Publishing

Nothing. Cut a GitHub release; `arch-repo`'s watcher opens a pull request
against itself within a day, builds it in a clean container, lints it, and on
green merges, signs, and pushes to both channels.

A packaging fix needs no release at all. `arch-repo` compares the rendered
recipe against what it last published, so a corrected recipe on the default
branch is picked up on its own and shipped as a `pkgrel` bump — `1.2.0-1`
becomes `1.2.0-2`, and resets to `-1` at the next genuine release.

To force a rebuild with nothing changed — a new soname to link against, a
recovered mis-push — bump `pkgrel` in `arch-repo`'s copy of the recipe and push
to `main`. The watcher leaves a hand-set `pkgrel` alone.

## Onboarding an existing package

1. Move the recipe to the default branch root, if it is somewhere else.
2. Delete whatever publishes to the AUR, and any documentation pointing at it.
3. Add the three make targets.
4. Cut a GitHub release if the project has only ever tagged.
5. Add `PKGBUILDs/<pkg>/` to `arch-repo` with an `upstream` script.

Steps 1 to 4 land on the default branch, which is where the recipe comes from,
so none of them needs a new tag. Each reaches users as `pkgrel` advancing.
