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
