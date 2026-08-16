# The three targets arch-repo's contract asks for. Copy into a source
# repository and adjust the language-specific lines; the names and what they
# promise do not change between repositories.
#
# There is no aur target. Publishing belongs to arch-repo, and a second writer
# to one AUR ref is how a PKGBUILD and its .SRCINFO drift apart.

VERSION := $(shell sed -n 's/^version = "\(.*\)"/\1/p' Cargo.toml 2>/dev/null || \
                   sed -n 's/.*"version": "\(.*\)".*/\1/p' package.json 2>/dev/null | head -1)

.PHONY: check package release version-guard

## Everything CI would run, plus the one thing only this repository can check
check: version-guard
	go vet ./...
	go test ./...

# The recipe's pkgver is a placeholder that arch-repo overwrites, so it is not
# one of the values compared here. What must agree is the tag about to be cut
# and the version the software reports about itself.
version-guard:
	@test -n "$(VERSION)" || { echo "no version found in the project manifest" >&2; exit 1; }
	@git rev-parse -q --verify "refs/tags/v$(VERSION)" >/dev/null \
	  && echo "v$(VERSION) is already tagged" \
	  || echo "v$(VERSION) not yet tagged — this is what the next release will be"

## Build ./PKGBUILD in a clean chroot and namcap the result — the pre-tag dry run
package:
	@command -v extra-x86_64-build >/dev/null || { echo "install devtools" >&2; exit 1; }
	@command -v updpkgsums >/dev/null        || { echo "install pacman-contrib" >&2; exit 1; }
	rm -rf build && mkdir -p build
	cp PKGBUILD $(wildcard *.install) build/
	cd build && sed -i 's/^pkgver=.*/pkgver=$(VERSION)/' PKGBUILD \
	  && updpkgsums \
	  && extra-x86_64-build \
	  && namcap PKGBUILD *.pkg.tar.zst

## Produce whatever artifacts the release must carry — usually nothing, because
## GitHub generates the source tarball the recipe consumes
release:
	@echo "nothing to build: the recipe reads GitHub's generated source tarball"
