# Steve — build & install the macOS menu-bar app.
#
# Usage (from the Steve/ directory, or `make -C Steve <target>` from the repo root):
#   make build     Build Steve.app (Release) into ./build
#   make install   Build, then install Steve.app into /Applications
#   make run       Install, then launch Steve.app
#   make test      Run the Swift package test suite
#   make clean     Remove build artifacts
#
# If /Applications is not writable on your machine, run:  sudo make install

SCHEME   := Steve
PROJECT  := Steve.xcodeproj
CONFIG   := Release
DERIVED  := build
APP      := Steve.app
APP_PATH := $(DERIVED)/Build/Products/$(CONFIG)/$(APP)
DEST     := /Applications

.PHONY: help build install run test uitest fixtures clean

help:
	@echo "Steve — make targets:"
	@echo "  build     Build $(APP) ($(CONFIG)) into ./$(DERIVED)"
	@echo "  install   Build, then install $(APP) into $(DEST)"
	@echo "  run       Install, then launch $(APP)"
	@echo "  test      Run the Swift test suite"
	@echo "  fixtures  Build, install, and launch $(APP) in fixture mode (--fixtures)"
	@echo "  uitest    Run the XCUITest suite"
	@echo "  clean     Remove build artifacts"

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
	  -destination 'platform=macOS' -derivedDataPath $(DERIVED) build

install: build
	@echo "→ Installing $(APP) into $(DEST)…"
	rm -rf "$(DEST)/$(APP)"
	ditto "$(APP_PATH)" "$(DEST)/$(APP)"
	@echo "✓ Installed $(DEST)/$(APP) — it runs in the menu bar (no Dock icon)."

run: install
	open "$(DEST)/$(APP)"

# Launch in fixture mode: the app boots with the canned six-skill scenario and
# auto-opens the Steve window on the Review tab with `diagnose` pre-selected.
# Passes `--fixtures` so FixtureMode.isActive returns true (ADR 0009).
fixtures: install
	open "$(DEST)/$(APP)" --args --fixtures

test:
	swift test --package-path .

uitest:
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) \
	  -destination 'platform=macOS' -derivedDataPath $(DERIVED) \
	  -only-testing:SteveUITests

clean:
	rm -rf $(DERIVED)
