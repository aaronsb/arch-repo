# Helpers for the per-package `upstream` scripts.
#
# The contract those scripts implement:
#
#   * cwd is the package directory, and $PWD/PKGBUILD exists
#   * exit 0 having printed nothing  -> already current, no work
#   * exit 0 having printed current=, current_rel=, version= and pkgrel=
#     -> PKGBUILD has been rewritten in place and those values describe the move
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

# The workflow decides whether to open a PR purely from these lines, so a
# script that rewrites the PKGBUILD without calling this has made a change that
# nothing will ever propose.
#
# Four values rather than two, because a bump is no longer always a version
# move. A recipe corrected under an unchanged version is a pkgrel bump, and
# `current` and `version` on their own can neither tell that apart from a no-op
# nor name a branch that does not collide with the last one. Both version
# fields stay bare pkgver so that a package's `notes` script still receives
# something it can look up upstream.
emit_bump() {
  printf 'current=%s\n'     "$1"
  printf 'current_rel=%s\n' "$2"
  printf 'version=%s\n'     "$3"
  printf 'pkgrel=%s\n'      "$4"
}

# --------------------------------------------------------------- inspection --

# Each of these reads PKGBUILD in the current directory unless handed another
# file, because sync_github_package has to ask the same questions of a recipe
# it has just fetched and of the one this repository has committed.

current_pkgver() { awk -F= '/^pkgver=/{print $2; exit}' "${1:-PKGBUILD}"; }
current_pkgrel() { awk -F= '/^pkgrel=/{print $2; exit}' "${1:-PKGBUILD}"; }

# Compares as versions, not strings: 3.9.10 is newer than 3.9.9, and a plain
# string test would have it the other way around.
is_newer() { [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]; }

# The file a PKGBUILD's install= names, or nothing if it names none.
#
# The field is shell, not a filename: fake-battery-nut writes
# install=${pkgname}.install. Reading it literally asks for a file whose name
# contains a dollar sign, and the 404 that comes back reads like a missing file
# rather than an unexpanded variable.
#
# _pkgname is expanded as well as pkgname, because a VCS recipe's pkgname ends
# in -git while the files beside it do not: example-app-git carries
# example-app.install, and only _pkgname names it.
#
# Expanded by substitution rather than by sourcing the recipe. Sourcing would
# handle every variable a PKGBUILD can define, and would also execute a file
# this repository has just fetched from a source repository, before anything has
# reviewed it.
install_file() {
  local f=${1:-PKGBUILD} inst name uname
  inst=$(awk -F= '/^install=/{gsub(/["'"'"']/,"",$2); print $2; exit}' "$f")
  [ -n "$inst" ] || return 0
  name=$(awk  -F= '/^pkgname=/{gsub(/[()'"'"'"]/,"",$2); print $2; exit}' "$f")
  uname=$(awk -F= '/^_pkgname=/{gsub(/[()'"'"'"]/,"",$2); print $2; exit}' "$f")
  printf '%s' "$inst" \
    | sed "s/\${_pkgname}/${uname}/g; s/\$_pkgname/${uname}/g; s/\${pkgname}/${name}/g; s/\$pkgname/${name}/g"
}

# The first real checksum in an array, or nothing if the recipe has no slot for
# one. The counterpart of set_first_sum, and it has to agree with it about which
# entry is "first" — see that function for why the match is written this way.
first_sum() {
  awk -v kind="$1" '
    !done && index($0, kind "sums=") == 1 { inarr = 1 }
    inarr && !done && match($0, /'"'"'[0-9a-fA-F]{64}'"'"'/) {
      print substr($0, RSTART + 1, RLENGTH - 2)
      done = 1
    }
  ' "${2:-PKGBUILD}"
}

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
    # Anchored at both ends, because a tag list carries no notion of a
    # pre-release and `sort -V` prefers one:
    #
    #   $ printf 'v1.2.0\nv1.2.0-rc1\n' | sort -V | tail -1
    #   v1.2.0-rc1
    #
    # So the first release candidate a repository tagged would have shipped as
    # the release. `releases/latest` above has no such problem — GitHub excludes
    # drafts and pre-releases from it, which is why ADR-100 asks our own
    # repositories to publish releases rather than bare tags. This path is for
    # upstreams that will never do that.
    v=$(curl -fsSL "https://api.github.com/repos/${repo}/tags" 2>/dev/null \
        | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        | grep -E '^v?[0-9]+(\.[0-9]+)+$' | sort -V | tail -1) || true
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
# It also means a source repository's own pkgver, pkgrel and sha256sums stop
# mattering: they are overwritten here, so their drifting stale — which is what
# they have all been doing — no longer reaches anyone.
#
# Two kinds of change reach users, and they are not the same event:
#
#   upstream tagged        pkgver moves, pkgrel restarts at 1
#   recipe changed only    pkgver holds, pkgrel is the committed one plus one
#
# The second used to be invisible. Detection was on the version alone, so a
# packaging fix pushed without a tag — a missing dependency, a wrong install
# path, a licence string namcap complains about — waited for whenever upstream
# next happened to cut a release. For our own projects that is months, and the
# person waiting is the one whose install is already broken.
#
# What is deliberately not detected is the source repository bumping its own
# pkgrel with no other change. pkgrel is this repository's count of how many
# times it has packaged a given release, so it is normalised away before the
# comparison and a bare bump upstream reads here as no change at all.
sync_github_package() {
  local repo=$1
  local version current current_rel rel work inst sha

  version=$(github_latest "$repo")
  test -n "$version"

  current=$(current_pkgver)
  current_rel=$(current_pkgrel)

  # Rendered somewhere else first. Writing straight over PKGBUILD would leave a
  # truncated recipe in the tree the moment a fetch failed halfway, and there is
  # no way to know whether there is anything to propose until the finished
  # rendering can be held up against what is committed.
  work=$(mktemp -d)
  curl -fsSL -o "$work/PKGBUILD" "https://raw.githubusercontent.com/${repo}/HEAD/PKGBUILD"
  test -s "$work/PKGBUILD"

  # A PKGBUILD's install= names a file that lives beside it, not a URL, so it
  # has to be fetched too or the recipe references something that was never
  # copied — and both the AUR push and a local makepkg would fail on it.
  inst=$(install_file "$work/PKGBUILD")
  if [ -n "$inst" ]; then
    curl -fsSL -o "$work/$inst" "https://raw.githubusercontent.com/${repo}/HEAD/${inst}"
    test -s "$work/$inst"
  fi

  # Only a genuinely newer tag moves pkgver. Upstream reporting what we already
  # ship is the ordinary case here, and it has to render to exactly what is
  # committed or every run would look like a change.
  if is_newer "$version" "$current"; then
    rel=1
  else
    version=$current
    rel=$current_rel
  fi
  set_release "$version" "$rel" "$work/PKGBUILD"

  # Not every package downloads a tarball. obsbot-camera-control sources git at
  # the tag and carries sha256sums=('SKIP'), so there is nothing to hash and no
  # slot to write into — makepkg reaches the same commit through the tag. A
  # recipe with no 64-hex entry is one of those, and asking anyway would
  # download an archive to compute a value with nowhere to go.
  if [ -n "$(first_sum sha256 "$work/PKGBUILD")" ]; then
    # The same tag names the same tarball, so the hash already committed here is
    # still the answer; fetching the archive again every night to recompute it
    # would buy nothing. A recipe that has only just grown a tarball has no
    # committed hash to reuse and falls through to fetching one.
    sha=""
    if [ "$version" = "$current" ]; then sha=$(first_sum sha256 PKGBUILD); fi
    if [ -z "$sha" ]; then
      sha=$(sha256_of_url "https://github.com/${repo}/archive/v${version}.tar.gz")
    fi
    test -n "$sha"
    set_first_sum sha256 "$sha" "$work/PKGBUILD"
  fi

  if ! recipe_changed "$work" "$inst"; then
    rm -rf "$work"
    return 0
  fi

  # Same software, packaged differently, which is the question pkgrel answers.
  if [ "$version" = "$current" ]; then
    rel=$((current_rel + 1))
    set_release "$version" "$rel" "$work/PKGBUILD"
  fi

  cp "$work/PKGBUILD" PKGBUILD
  if [ -n "$inst" ]; then cp "$work/$inst" "$inst"; fi
  rm -rf "$work"

  emit_bump "$current" "$current_rel" "$version" "$rel"
}

# Whether the recipe rendered into $1 says anything different from the one this
# repository has committed. Only the files sync_github_package would go on to
# copy into place are compared, since those are the whole of what it changes.
#
# A missing committed install file counts as a difference rather than an error:
# a recipe that grows an install= hook has changed, and the fetch above already
# has the file it needs.
recipe_changed() {
  local work=$1 inst=$2
  cmp -s "$work/PKGBUILD" PKGBUILD || return 0
  [ -z "$inst" ] || cmp -s "$work/$inst" "$inst" || return 0
  return 1
}

# ------------------------------------------------------------------ rewrite --

# Both halves of the version are written together because a package version is
# only meaningful as a pair: 1.2.0-3 is a complete answer and 1.2.0 is not.
# Splitting them invited the bug this replaced, where writing pkgver silently
# reset pkgrel to 1 and a repackaging of an unchanged release could not be
# expressed at all.
#
# A watcher that fires only on a new upstream release passes 1: carrying the old
# pkgrel forward would claim this is the second packaging of a release that has
# only been packaged once.
set_release() {
  sed -i "s/^pkgver=.*/pkgver=$1/; s/^pkgrel=.*/pkgrel=$2/" "${3:-PKGBUILD}"
}

# Replaces the first real checksum in an array. Every PKGBUILD here puts the
# upstream artifact first and local files or SKIP entries after it, so "first"
# is the one that moves with the version.
#
# Matching the first 64-hex token from the sums= line onward, rather than
# anchoring to the opening quote on that same line, because both layouts are in
# use here:
#
#   sha256sums=('abc...' 'SKIP')      ya-claude, mlterm-fb
#   sha256sums=(                      bosectl-qt
#       'abc...'
#       'SKIP'
#   )
#
# The anchored version silently did nothing on the second form — no error, and
# the old hash left in place next to a new pkgver, which is a build failure at
# best and the wrong payload at worst. SKIP is never matched: it is not hex.
set_first_sum() {
  local kind=$1 sum=$2 file=${3:-PKGBUILD}
  awk -v kind="$kind" -v sum="$sum" '
    !done && index($0, kind "sums=") == 1 { inarr = 1 }
    inarr && !done && match($0, /'"'"'[0-9a-fA-F]{64}'"'"'/) {
      $0 = substr($0, 1, RSTART) sum substr($0, RSTART + RLENGTH - 1)
      done = 1
    }
    { print }
  ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}
