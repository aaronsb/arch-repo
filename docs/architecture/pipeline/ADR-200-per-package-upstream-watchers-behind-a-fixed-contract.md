---
status: Accepted
date: 2026-08-16
deciders:
  - aaronsb
  - claude
related:
  - ADR-300
---

# ADR-200: Per-package upstream watchers behind a fixed contract

## Context

Watching upstream for new releases started as one hand-written CI job per
package. With two packages that was tolerable duplication. Adding a third and
fourth made it clear the duplication was hiding a wrong assumption: that
discovery is a shared problem with a shared answer.

It is not. The four packages in play find their current version four different
ways, and no two are close:

| Package | How the current version is found |
|---|---|
| `ya-claude` | GPG-signed apt index; version and hash read from `Packages` after `InRelease` verifies |
| `ya-claude-code` | Unsigned `latest` pointer selects a release; a GPG-signed manifest authenticates it |
| `mlterm-fb` | GitHub *releases* (named `3.9.5`); the git *tags* stopped at `rel-3_9_1`, and the tarball comes from SourceForge |
| `brother-hl-l3295cdw` | An HTML download page, carrying both the version and an opaque `dlf105748` id the source URL needs |

A generic "read the newest tag" watcher serves none of these. It would report a
version four releases stale for `mlterm-fb`, and has nothing to read at all for
the other three.

Discovery also cannot be reduced to "return a version and a checksum". Brother's
source URL embeds a file id that changes independently of the version, so the
rewrite a bump performs is package-specific, not just two field substitutions.

What *is* common is everything after discovery: compare against the packaged
version, open a pull request, build it, gate it, merge it, publish it.

## Decision

Each package owns its own discovery, as an executable in its own directory. The
workflow owns everything else and names no package.

`PKGBUILDs/<pkg>/` may carry:

- **`upstream`** — required to be watched. Runs with cwd set to the package
  directory. Prints nothing when already current. When not, it rewrites the
  PKGBUILD in place and prints `current=`, `current_rel=`, `version=` and
  `pkgrel=`. That output is already `GITHUB_OUTPUT` syntax, so the workflow
  redirects it rather than parsing it.
- **`notes`** — optional. Run as `notes <current> <new>`; stdout is appended to
  the pull request body. Consulted only when `version` differs from `current`,
  since upstream publishes no changelog for a repackaging.
- **`.no-auto-merge`** — optional. Its presence holds the pull request for a
  human even when the build is green.
- **`.namcap-allow`** — optional. Regexes for namcap errors this package
  knowingly accepts; anything else fails the build.
- **`.aur-deps`** — optional. Dependency names that live in the AUR rather than
  in any repository pacman can reach. Each gets a stub built and installed
  before the build, because `makepkg -s` cannot resolve them and has no
  per-dependency escape. The names stay in `depends()`.

Shared helpers live in `PKGBUILDs/lib/upstream.sh`. `github_latest` asks for
releases and falls back to tags, because the two disagree in both directions
across these projects — `obsbot-camera-control` and `yay-friend` tag without
releasing, while `mlterm` releases without tagging.

Both workflows read their package list from the tree rather than a written-down
matrix. This is not tidiness: branch protection names required contexts as
strings, so a package added to a hardcoded matrix arrives ungated, and one
removed leaves a rule nothing can satisfy. A single `gate` job aggregates the
matrix and is the only required context.

### A bump is not always a version move

The contract reports a full `pkgver`-`pkgrel` pair on both sides, because two
different events reach a user through it:

| What happened | What the watcher writes |
|---|---|
| Upstream tagged a new release | `pkgver` moves, `pkgrel` restarts at 1 |
| The recipe changed with no new tag | `pkgver` holds, `pkgrel` is the committed one plus one |

The second only arises for packages whose recipe `arch-repo` fetches rather than
stores — the ones [[ADR-300]] describes. There, detecting on the version alone
meant a packaging fix pushed without a tag waited, unpublished, for an unrelated
release to carry it, and for a project that releases twice a year the person
waiting is the one whose install is already broken. `sync_github_package`
therefore fetches the recipe on every run, renders it to what this repository
would publish, and holds that up against the committed file. Identical is the
ordinary outcome, and it prints nothing.

`pkgrel` is `arch-repo`'s count of how many times it has packaged a given
release, so it is normalised out of that comparison: a source repository bumping
its own `pkgrel` and changing nothing else reads here as no change at all.

Naming follows from this. `bump/<pkg>-<version>` stops being unique once the
version can hold still, so branches, titles and commit messages all carry
`<version>-<pkgrel>` — the only form of an Arch package version that names one
build. Reusing the branch would have reopened last week's pull request and
merged a stale recipe under a title that read correctly.

## Consequences

### Positive

- Adding a package is adding a directory. No workflow edit, no ruleset edit.
- A package whose upstream is strange pays for its own strangeness. Brother's
  HTML scraping cannot destabilise the Claude packages' signature checks.
- The verification each package performs stays visible in that package, next to
  the PKGBUILD that re-runs it at build time.
- `.no-auto-merge` makes the trust distinction explicit and per-package rather
  than a global policy. `ya-claude` is signature-verified end to end and merges
  itself; `mlterm-fb` has no upstream signatures at all and waits for a reader.

### Negative

- Four watchers instead of one means four places a bug can live, and shared
  helper changes must be checked against every caller.
- The contract is enforced by convention rather than by a type. A script that
  rewrites a PKGBUILD without calling `emit_bump` makes a change nothing will
  propose, and nothing catches that but review.
- A fetched recipe is downloaded on every scheduled run rather than only after a
  tag. The tarball is still fetched only when the version moves, so the standing
  cost is one small request per package per day.
- `arch-repo`'s copy of a fetched recipe cannot be edited here. An edit is
  reverted on the next run and charged as a `pkgrel` bump — the intended
  direction of authority, but the revert arrives as a pull request that looks
  like an upstream change rather than as an error.

### Neutral

- Watchers are ordinary shell scripts runnable outside CI, which is how both
  ported ones were verified: roll the PKGBUILD back, run the script, confirm the
  result is byte-identical to the committed file. Content detection is checked
  the same way from the other side — perturb the committed recipe, run the
  script, confirm it is restored and `pkgrel` has advanced by one.
- The pattern is portable. A repository that publishes its own package can carry
  the same three files, which is what [[ADR-300]] builds on.

## Alternatives Considered

- **One generic watcher reading git tags.** Rejected on the evidence above: it
  reports a stale version for `mlterm-fb` and cannot read the other three at all.
- **A declarative per-package config file** (`upstream.yaml` naming a strategy
  and its parameters). Rejected because every package needed a different
  strategy anyway, so the config would be a thin wrapper around per-package code
  with a schema in between. Brother alone — scraping two values out of HTML and
  rewriting a URL fragment — would have needed an escape hatch back to code.
- **Watchers as workflow steps** rather than files in the package. Rejected: it
  is the arrangement being replaced, and it puts a package's upstream knowledge
  in a file that every other package also edits.
- **Requiring a tag for every packaging fix**, leaving detection on the version
  alone. Rejected: it asks a project to cut a release of software that did not
  change, and fills its version history with numbers that describe nothing a
  reader of the changelog can act on. `pkgrel` is the field Arch provides for
  precisely this distinction, and it was going unused.
- **Storing a hash of the last-seen upstream recipe** beside the PKGBUILD and
  comparing against that. Rejected as a second source of truth: the committed
  PKGBUILD already records what was last accepted, and a stored hash is one more
  thing that can disagree with it.
