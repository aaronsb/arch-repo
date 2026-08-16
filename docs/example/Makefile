# The three targets arch-repo's packaging contract asks for. Copy into a source
# repository and adjust the language-specific lines; the names and what they
# promise do not change between repositories.
#
# There is no aur target. Publishing belongs to arch-repo, and a second writer
# to one AUR ref is how a PKGBUILD and its .SRCINFO drift apart.

# The AUR package name, and the directory the tarball extracts to. They differ
# whenever the repository is not named after the package — markdown-mixed-media
# publishes mmm — so SRCNAME must match what build() cds into, not pkgname.
NAME    := $(shell sed -n 's/^pkgname=//p' PKGBUILD)
SRCNAME := $(or $(shell sed -n 's/^_repo=//p' PKGBUILD),$(NAME))

# Wherever this project already records its version. One line to change.
VERSION := $(shell sed -n 's/^version = "\(.*\)"/\1/p' Cargo.toml 2>/dev/null | head -1)

.PHONY: help check package release version test lint

help: ## List targets
	@grep -hE '^[a-z-]+:.*##' $(MAKEFILE_LIST) | sed 's/:.*## /\t/' | expand -t20

check: version lint test ## Everything CI would run

lint:
	cargo clippy -- -D warnings

test:
	cargo test

# PKGBUILD's pkgver is a placeholder arch-repo overwrites, so it is not one of
# the values compared here. What has to agree is the tag about to be cut and the
# version the software reports about itself. Reporting rather than failing:
# before a release the tag is legitimately absent and after one it is
# legitimately present, so neither state is an error on its own.
version: ## Report the version this repository would release
	@test -n "$(VERSION)" || { echo "no version found in the project manifest" >&2; exit 1; }
	@test -n "$(NAME)"    || { echo "no pkgname in PKGBUILD" >&2; exit 1; }
	@if git rev-parse -q --verify "refs/tags/v$(VERSION)" >/dev/null; then \
	    echo "$(NAME) $(VERSION) — v$(VERSION) is already tagged"; \
	else \
	    echo "$(NAME) $(VERSION) — not yet tagged; this is what the next release will be"; \
	fi

package: version ## Build ./PKGBUILD in a clean chroot and namcap it
	@command -v extra-x86_64-build >/dev/null || { echo "needs devtools" >&2; exit 1; }
	@command -v namcap >/dev/null            || { echo "needs namcap" >&2; exit 1; }
	rm -rf build && mkdir -p build
	# The tarball the release would carry, built from HEAD and named exactly
	# what the recipe's source= resolves to, so makepkg finds it locally.
	# Letting updpkgsums fetch the published archive instead would need the tag
	# to already exist, which makes a pre-release dry run impossible — the
	# circularity arch-repo removes on its own side.
	git archive --format=tar.gz --prefix=$(SRCNAME)-$(VERSION)/ \
	    -o build/$(NAME)-$(VERSION).tar.gz HEAD
	cp PKGBUILD $(wildcard *.install) build/
	# Slot one only — the entry that moves with the version, and the one
	# arch-repo writes. updpkgsums rewrites every entry, so a recipe whose
	# later sources carry SKIP (a git checkout, a local file) would have them
	# replaced with computed hashes and the dry run would build something
	# arch-repo will never publish. The sums array is the only quoted 64-hex
	# in a recipe, and SKIP is never matched: it is not hex.
	cd build \
	  && sed -i 's/^pkgver=.*/pkgver=$(VERSION)/' PKGBUILD \
	  && sum=$$(sha256sum $(NAME)-$(VERSION).tar.gz | cut -d' ' -f1) \
	  && sed -i "0,/'[0-9a-f]\{64\}'/s//'$$sum'/" PKGBUILD
	cd build && extra-x86_64-build
	# namcap exits 0 whether or not it found errors, so its output is what
	# decides. Same rule arch-repo's gate uses: errors fail, warnings do not,
	# and a package may allow specific errors by listing regexes in
	# .namcap-allow. Debug packages are excluded because every .build-id entry
	# in one is a symlink into the main package, which namcap calls dangling.
	cd build && namcap PKGBUILD $$(ls ./*.pkg.tar.zst | grep -v -- '-debug-') | tee namcap.txt
	@cd build && if [ -f ../.namcap-allow ]; then \
	    bad=$$(grep ' E: ' namcap.txt | grep -vE -f ../.namcap-allow || true); \
	  else \
	    bad=$$(grep ' E: ' namcap.txt || true); \
	  fi; \
	  if [ -n "$$bad" ]; then echo "namcap errors:"; printf '%s\n' "$$bad"; exit 1; fi; \
	  echo "namcap: no errors"

release: ## Produce the artifacts a release must carry
	@echo "nothing to build — the recipe reads the source tarball GitHub generates"
