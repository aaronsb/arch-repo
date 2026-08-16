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
  PKGBUILD in place and prints `current=` and `version=`. That output is already
  `GITHUB_OUTPUT` syntax, so the workflow redirects it rather than parsing it.
- **`notes`** — optional. Run as `notes <current> <new>`; stdout is appended to
  the pull request body.
- **`.no-auto-merge`** — optional. Its presence holds the pull request for a
  human even when the build is green.

Shared helpers live in `PKGBUILDs/lib/upstream.sh`. `github_latest` asks for
releases and falls back to tags, because the two disagree in both directions
across these projects — `obsbot-camera-control` and `yay-friend` tag without
releasing, while `mlterm` releases without tagging.

Both workflows read their package list from the tree rather than a written-down
matrix. This is not tidiness: branch protection names required contexts as
strings, so a package added to a hardcoded matrix arrives ungated, and one
removed leaves a rule nothing can satisfy. A single `gate` job aggregates the
matrix and is the only required context.

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
  rewrites a PKGBUILD without printing `current=`/`version=` makes a change
  nothing will propose, and nothing catches that but review.

### Neutral

- Watchers are ordinary shell scripts runnable outside CI, which is how both
  ported ones were verified: roll the PKGBUILD back, run the script, confirm the
  result is byte-identical to the committed file.
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
