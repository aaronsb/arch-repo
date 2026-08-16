# A conforming source repository

What a repository provides so `arch-repo` can build, lint, sign and publish it.
Copy these into a project and adjust the language-specific lines.

| File | What it shows |
|---|---|
| `PKGBUILD` | the versioned shape — placeholders `arch-repo` overwrites, SPDX licence handling, `install=` as shell rather than a filename |
| `PKGBUILD-git` | the VCS shape — `pkgver()` derived from `git describe` instead of hardcoded, `sha256sums=('SKIP')` |
| `example-app.install` | a hicolor cache hook, and the two dependencies namcap complains about in opposite directions |
| `Makefile` | `check`, `package`, `release`, and the absence of anything that publishes |
| `verify` | reads the above with `PKGBUILDs/lib/upstream.sh` and asserts what it extracts |

`verify` runs in CI as the `contract` job, which `gate` requires. An example
that is only prose rots silently — the helpers change, the sample stops being
something they can parse, and nothing says so until a repository written against
it fails to onboard.

The rules are in [`../packaging-contract.md`](../packaging-contract.md); the
reasoning is in
[ADR-100](../architecture/packaging/ADR-100-one-packaging-contract-for-every-repository-arch-repo-publishes.md).
