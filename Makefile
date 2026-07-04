# GRYPD iOS app — common development workflows
#
# This Makefile wraps xcodegen + xcodebuild so everyday commands are short and
# reproducible. The project is generated from app/project.yml, so always run
# `make generate` (or any target that depends on it) before opening Xcode.
#
# Override the target simulator with:
#   make run DEVICE="iPhone 15 Pro"

PROJECT      := app/GRYPD.xcodeproj
SCHEME       := GRYPD
BUNDLE_ID    := sh.saad.grypd
DERIVED_DATA := app/build/DerivedData
ARCHIVE_PATH := app/build/GRYPD.xcarchive
IPA_PATH     := app/build/GRYPD.ipa
EXPORT_PLIST := app/build/ExportOptions.plist

# App Store Connect API key for TestFlight upload.
# Get these from App Store Connect > Users and Access > Keys.
# Values are read from a gitignored .env in the repo root (copy .env.example),
# so `make beta` needs no arguments once .env is filled in. You can still
# override any value on the command line: `make beta API_KEY_ID=...`.
-include .env
API_KEY_ID    ?=
API_ISSUER_ID ?=
API_KEY_PATH  ?=

# Cloudflare Pages project serving grypd.saad.sh (read from .env, like the keys
# above). Wrangler auth comes from the environment (`npx wrangler login`).
CF_PAGES_PROJECT ?=
CF_PAGES_BRANCH  ?= main

# Default simulator: use whichever iOS Simulator is already booted, otherwise
# fall back to a device that ships with the current Xcode SDK.
BOOTED_DEVICE := $(shell xcrun simctl list devices 'iOS' booted -j | \
	python3 -c "import sys,json; d=json.load(sys.stdin); devs=[dev for pool in d['devices'].values() for dev in pool if dev.get('state')=='Booted']; print(devs[0]['name'] if devs else '')")
DEVICE       ?= $(if $(BOOTED_DEVICE),$(BOOTED_DEVICE),iPhone 17 Pro)
SIM_DEST     := platform=iOS Simulator,name=$(DEVICE)

.DEFAULT_GOAL := help

.PHONY: help catalog site deploy-docs py-check py-lint py-format generate build run test clean open archive beta export upload organizer

help:
	@echo "GRYPD iOS development commands"
	@echo ""
	@echo "  make catalog   - Build catalog JSON from Weekly Workouts.dtable"
	@echo "  make site      - Build the docs site (site/) and sync it into dist/"
	@echo "  make deploy-docs - Build docs and deploy dist/ to Cloudflare Pages (grypd.saad.sh)"
	@echo "  make py-check  - Run Python lint, syntax checks, and pipeline tests"
	@echo "  make py-format - Format Python pipeline code with Ruff"
	@echo "  make generate  - Regenerate the Xcode project from app/project.yml"
	@echo "  make build     - Build GRYPD for the iOS Simulator"
	@echo "  make run       - Build, install, and launch GRYPD on the iOS Simulator"
	@echo "  make test      - Run GRYPDUnitTests on the iOS Simulator"
	@echo "  make clean     - Remove local build artifacts"
	@echo "  make open      - Regenerate project and open it in Xcode"
	@echo "  make archive   - Create a Release archive"
	@echo "  make beta      - Archive, export .ipa, and upload to TestFlight"
	@echo "  make export    - Export an .ipa from the existing archive"
	@echo "  make upload    - Upload the existing .ipa to TestFlight"
	@echo "  make organizer - Open the archive in Xcode Organizer for manual upload"
	@echo ""
	@echo "Override the simulator with: make run DEVICE='iPhone 15 Pro'"
	@echo "Upload example: make beta API_KEY_ID=... API_ISSUER_ID=... API_KEY_PATH=.../AuthKey_xxx.p8"

# Build the app/offline catalog and R2 publish payload from a SeaTable export.
# Override with: make catalog DTABLE=/path/to/Weekly\ Workouts.dtable
DTABLE ?= Weekly Workouts.dtable
catalog:
	@echo "→ Building catalog from $(DTABLE)..."
	python3 pipeline/build_catalog.py "$(DTABLE)"

# Build the docs site (site/, Vite + React) and sync its static output into
# dist/ alongside the catalog JSON, so grypd.saad.sh/ serves the docs while
# grypd.saad.sh/manifest.json etc. keep serving the catalog. dist/assets,
# dist/screenshots, the top-level *.html files, and icon-*.png are owned
# exclusively by the docs site (the catalog pipeline only ever writes
# top-level *.json + _headers), so they're wiped and rewritten on every
# build. That's what prevents a renamed or removed page (or a stale
# content-hashed JS/CSS bundle) from lingering as an orphan in dist/.
site:
	@echo "→ Building docs site..."
	cd site && npm install && npm run build
	@echo "→ Syncing docs site into dist/..."
	mkdir -p dist
	rm -rf dist/assets dist/screenshots
	rm -f dist/*.html dist/icon-*.png
	cp site/build/*.html site/build/*.png dist/
	cp -R site/build/assets dist/assets
	cp -R site/build/screenshots dist/screenshots

# Deploy the docs to Cloudflare Pages via Wrangler direct upload (no Git
# integration, no catalog regen). A Pages deploy replaces the whole deployment,
# so we upload all of dist/ — the committed catalog JSON rides along unchanged.
deploy-docs: site
	@test -n "$(CF_PAGES_PROJECT)" || { echo "✗ CF_PAGES_PROJECT is not set (add it to .env). See .env.example."; exit 1; }
	@echo "→ Deploying dist/ to Cloudflare Pages project '$(CF_PAGES_PROJECT)' (branch $(CF_PAGES_BRANCH))..."
	npx wrangler pages deploy dist --project-name=$(CF_PAGES_PROJECT) --branch=$(CF_PAGES_BRANCH)

py-lint:
	@echo "→ Linting Python with Ruff..."
	uvx ruff check pipeline

py-format:
	@echo "→ Formatting Python with Ruff..."
	uvx ruff format pipeline

py-check: py-lint
	@echo "→ Checking Python syntax..."
	python3 -m py_compile pipeline/*.py
	@echo "→ Validating generated JSON contract..."
	python3 pipeline/validate_outputs.py
	@echo "→ Running pipeline tests..."
	python3 -m unittest discover -s pipeline -p 'test_*.py'

# Regenerate the Xcode project whenever project.yml changes.
generate:
	@echo "→ Generating Xcode project..."
	cd app && xcodegen generate

# Build the app for the selected iOS Simulator.
build: generate
	@echo "→ Building $(SCHEME) for $(DEVICE)..."
	xcodebuild -project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination '$(SIM_DEST)' \
		-derivedDataPath $(DERIVED_DATA) \
		build

# Build the app, install it on the selected simulator, and launch it.
run: build
	@echo "→ Launching $(SCHEME) on $(DEVICE)..."
	@DEVICE_ID=$$(xcrun simctl list devices 'iOS' available -j | \
		python3 -c "import sys,json; d=json.load(sys.stdin); devs=[dev for pool in d['devices'].values() for dev in pool if dev.get('name')=='$(DEVICE)' and dev.get('isAvailable')]; print(devs[0]['udid'] if devs else '')"); \
	if [ -z "$$DEVICE_ID" ]; then \
		echo "❌ Simulator '$(DEVICE)' not found."; \
		echo "   Run: xcrun simctl list devices"; \
		exit 1; \
	fi; \
	echo "   Using simulator $$DEVICE_ID"; \
	xcrun simctl boot $$DEVICE_ID 2>/dev/null || true; \
	open -a Simulator; \
	sleep 2; \
	APP_PATH=$$(find $(DERIVED_DATA) -name '$(SCHEME).app' -type d | head -n 1); \
	if [ -z "$$APP_PATH" ]; then \
		echo "❌ Built .app not found in $(DERIVED_DATA)"; \
		exit 1; \
	fi; \
	echo "   Installing $$APP_PATH"; \
	xcrun simctl install $$DEVICE_ID "$$APP_PATH"; \
	echo "   Launching $(BUNDLE_ID)"; \
	xcrun simctl launch $$DEVICE_ID $(BUNDLE_ID)

# Run the unit-test target on the selected simulator.
test: generate
	@echo "→ Running $(SCHEME) unit tests..."
	xcodebuild -project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination '$(SIM_DEST)' \
		-derivedDataPath $(DERIVED_DATA) \
		test

# Remove derived data and local archives so the next build is fresh.
clean:
	-rm -rf $(DERIVED_DATA)
	-rm -rf $(ARCHIVE_PATH)
	-rm -rf ~/Library/Developer/Xcode/DerivedData/GRYPD-*

# Generate the project and open it in Xcode.
open: generate
	open $(PROJECT)

# Create a Release archive suitable for App Store distribution.
archive: generate
	@echo "→ Archiving $(SCHEME) for release..."
	xcodebuild -project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'generic/platform=iOS' \
		-allowProvisioningUpdates \
		archive \
		-archivePath $(ARCHIVE_PATH)

# Export an .ipa from the existing archive.
export:
	@if [ ! -d "$(ARCHIVE_PATH)" ]; then \
		echo "❌ Archive not found at $(ARCHIVE_PATH). Run 'make archive' first."; \
		exit 1; \
	fi
	@echo "→ Exporting $(IPA_PATH)..."
	@mkdir -p app/build
	@rm -f $(EXPORT_PLIST)
	/usr/libexec/PlistBuddy -c "Add :method string app-store" $(EXPORT_PLIST)
	/usr/libexec/PlistBuddy -c "Add :signingStyle string automatic" $(EXPORT_PLIST)
	/usr/libexec/PlistBuddy -c "Add :teamID string 2ZPA772V9V" $(EXPORT_PLIST)
	/usr/libexec/PlistBuddy -c "Add :stripSwiftSymbols bool true" $(EXPORT_PLIST)
	/usr/libexec/PlistBuddy -c "Add :thinning string '<none>'" $(EXPORT_PLIST)
	xcodebuild -exportArchive \
		-archivePath $(ARCHIVE_PATH) \
		-exportPath app/build \
		-exportOptionsPlist $(EXPORT_PLIST) \
		-allowProvisioningUpdates

# Upload the existing .ipa to TestFlight.
upload:
	@if [ ! -f "$(IPA_PATH)" ]; then \
		echo "❌ .ipa not found at $(IPA_PATH). Run 'make export' first."; \
		exit 1; \
	fi
	@if [ -z "$(API_KEY_ID)" ] || [ -z "$(API_ISSUER_ID)" ] || [ -z "$(API_KEY_PATH)" ]; then \
		echo "❌ Set API_KEY_ID, API_ISSUER_ID, and API_KEY_PATH to upload."; \
		echo "   Example: make upload API_KEY_ID=ABC123 API_ISSUER_ID=... API_KEY_PATH=.../AuthKey_ABC123.p8"; \
		exit 1; \
	fi
	@echo "→ Uploading $(IPA_PATH) to TestFlight..."
	xcrun altool --upload-app --type ios --file $(IPA_PATH) --apiKey $(API_KEY_ID) --apiIssuer $(API_ISSUER_ID)

# Full TestFlight release pipeline: archive, export, upload.
beta: archive export upload

# Open the archive in Xcode Organizer for manual upload.
organizer: archive
	open $(ARCHIVE_PATH)
