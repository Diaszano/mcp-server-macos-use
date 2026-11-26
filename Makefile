SHELL := /bin/sh

# swiftlint needs SourceKit from Xcode, not from the CommandLineTools that xcode-select may point at.
ifeq ($(origin DEVELOPER_DIR), undefined)
ifneq ($(wildcard /Applications/Xcode.app/Contents/Developer),)
export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
endif
endif

# The system swift is mismatched with the SDK; always use the Xcode toolchain.
SWIFT ?= xcrun --toolchain com.apple.dt.toolchain.XcodeDefault swift
# `make dist SWIFT_FLAGS="--arch arm64 --arch x86_64"` builds universal binaries (the release workflow does).
SWIFT_FLAGS ?=
SWIFT_FORMAT_CONFIG := .swift-format
SWIFT_PATHS := Sources Tests
BINARIES := mcp-server-macos-use screenshot-helper

.PHONY: build release dist test fmt fmt-check lint lint-fix verify clean hooks check-commits check-branch

build:
	$(SWIFT) build $(SWIFT_FLAGS)

release:
	$(SWIFT) build -c release $(SWIFT_FLAGS)

# Packages both binaries into build/mcp-server-macos-use-$(VERSION).tar.gz
dist: release
	@test -n "$(VERSION)" || { echo "usage: make dist VERSION=x.y.z" >&2; exit 1; }
	rm -rf build/dist && mkdir -p build/dist
	bin="$$($(SWIFT) build -c release $(SWIFT_FLAGS) --show-bin-path)"; \
		for b in $(BINARIES); do cp "$$bin/$$b" build/dist/; done
	tar -C build/dist -czf build/mcp-server-macos-use-$(VERSION).tar.gz $(BINARIES)

test:
	$(SWIFT) test

fmt:
	$(SWIFT) format format --configuration $(SWIFT_FORMAT_CONFIG) --in-place --recursive --parallel $(SWIFT_PATHS)

fmt-check:
	$(SWIFT) format lint --configuration $(SWIFT_FORMAT_CONFIG) --strict --recursive --parallel $(SWIFT_PATHS)

lint:
	swiftlint lint --strict --config .swiftlint.yml

lint-fix:
	swiftlint lint --fix --config .swiftlint.yml

verify: fmt-check lint test

clean:
	rm -rf build .build

hooks:
	git config core.hooksPath .githooks
	@echo "Configured git hooks via .githooks"

check-commits:
	@sh ./scripts/verify-commits.sh origin/main HEAD

check-branch:
	@sh ./scripts/verify-branch.sh
