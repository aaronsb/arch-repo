# Helpers for the per-package `upstream` scripts.
#
# The contract those scripts implement:
#
#   * cwd is the package directory, and $PWD/PKGBUILD exists
#   * exit 0 having printed nothing  -> already current, no work
#   * exit 0 having printed current= and version= -> PKGBUILD has been rewritten
#     in place and those two values describe the move
#   * any other exit -> the run fails loudly
#
# Discovery lives in the package rather than the workflow because it does not
# generalise. Anthropic publishes a signed apt index, Anthropic again publishes a
# signed manifest behind a `latest` pointer, mlterm tags nothing usable and ships
# tarballs from SourceForge, and Brother has an HTML page with an opaque file id.
# A single "read the tags" watcher would serve none of them. What does
# generalise is everything after discovery, and that is what the workflow keeps.

set -euo pipefail

# ---------------------------------------------------------------- reporting --

# The workflow decides whether to open a PR purely from these two lines, so a
# script that rewrites the PKGBUILD without calling this has made a change that
# nothing will ever propose.
emit_bump() {
  printf 'current=%s\n' "$1"
  printf 'version=%s\n'  "$2"
}

current_pkgver() { awk -F= '/^pkgver=/{print $2; exit}' PKGBUILD; }

# Compares as versions, not strings: 3.9.10 is newer than 3.9.9, and a plain
# string test would have it the other way around.
is_newer() { [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]; }

# ---------------------------------------------------------------- discovery --

# Newest release tag for a GitHub repository, with the leading v stripped.
#
# Releases are asked for first and tags are the fallback, because the two
# disagree in both directions across these projects: obsbot-camera-control and
# yay-friend tag without ever cutting a release, while mlterm cuts releases
# named 3.9.5 whose underlying tags stopped at rel-3_9_1. Taking whichever
# exists, releases first, is the only rule that gets both right.
github_latest() {
  local repo=$1 v
  v=$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
      | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1) || true
  if [ -z "${v:-}" ]; then
    v=$(curl -fsSL "https://api.github.com/repos/${repo}/tags" 2>/dev/null \
        | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        | grep -E '^v?[0-9]+\.[0-9]+' | sort -V | tail -1) || true
  fi
  printf '%s' "${v#v}"
}

sha256_of_url() {
  local tmp; tmp=$(mktemp)
  curl -fsSL -o "$tmp" "$1"
  sha256sum "$tmp" | cut -d' ' -f1
  rm -f "$tmp"
}

md5_of_url() {
  local tmp; tmp=$(mktemp)
  curl -fsSL -o "$tmp" "$1"
  md5sum "$tmp" | cut -d' ' -f1
  rm -f "$tmp"
}

# ------------------------------------------------- packages we publish ourselves --

# For a package whose recipe lives in its own source repository.
#
# The recipe is taken from the default branch, not from the tag, and this is not
# a shortcut. A PKGBUILD cannot carry the checksum of the tarball its own tag
# produces — the hash only exists once the tag does — so at v0.5.3 playtimed's
# PKGBUILD still read pkgver=0.5.2 with the 0.5.2 hash, and every one of these
# repositories had a Makefile target to go back and fix that afterwards. Taking
# the recipe from the branch and both moving values from the tag removes the
# circularity rather than automating a walk around it.
#
# It also means a source repository's own pkgver and sha256sums stop mattering:
# they are overwritten here, so their drifting stale — which is what they have
# all been doing — no longer reaches anyone.
#
# Detection is on the version only. A recipe edited without a new tag rides
# along with the next bump.
sync_github_package() {
  local repo=$1 version current sha tarball
  version=$(github_latest "$repo")
  test -n "$version"

  current=$(current_pkgver)
  is_newer "$version" "$current" || return 0

  curl -fsSL -o PKGBUILD "https://raw.githubusercontent.com/${repo}/HEAD/PKGBUILD"
  test -s PKGBUILD

  # A PKGBUILD's install= names a file that lives beside it, not a URL, so it
  # has to be fetched too or the recipe references something that was never
  # copied — and both the AUR push and a local makepkg would fail on it.
  local inst
  inst=$(awk -F= '/^install=/{gsub(/["'"'"']/,"",$2); print $2; exit}' PKGBUILD)
  if [ -n "$inst" ]; then
    curl -fsSL -o "$inst" "https://raw.githubusercontent.com/${repo}/HEAD/${inst}"
    test -s "$inst"
  fi

  tarball="https://github.com/${repo}/archive/v${version}.tar.gz"
  sha=$(sha256_of_url "$tarball")
  test -n "$sha"

  set_pkgver "$version"
  set_first_sum sha256 "$sha"
  emit_bump "$current" "$version"
}

# ------------------------------------------------------------------ rewrite --

set_pkgver() {
  sed -i "s/^pkgver=.*/pkgver=$1/" PKGBUILD
  # A new upstream version restarts the packaging revision. Carrying the old
  # pkgrel forward would claim this is the second packaging of a release that
  # has only been packaged once.
  sed -i "s/^pkgrel=.*/pkgrel=1/" PKGBUILD
}

# Replaces the first entry of a checksum array. Every PKGBUILD here puts the
# upstream artifact first and local files after it, so "first" is the one that
# moves with the version; the rest are files in this repository whose hashes
# have nothing to do with upstream.
set_first_sum() {
  local kind=$1 sum=$2
  sed -i "0,/^${kind}sums=('[^']*'/s//${kind}sums=('${sum}'/" PKGBUILD
}
