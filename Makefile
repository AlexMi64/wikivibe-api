# Native macOS development and local ad-hoc DMG packaging.
# Developer ID signing, notarization and publishing are not configured.
ifeq (,$(DEVELOPER_DIR))
ifneq (,$(wildcard /Applications/Xcode.app/Contents/Developer))
export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
endif
endif

PROJECT := WikiVibe.xcodeproj
SCHEME := WikiVibe
RESOLVED_PACKAGES := $(PROJECT)/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
ARCH ?= $(shell uname -m)
DEST ?= platform=macOS,arch=$(ARCH)
DERIVED_DATA ?= build/DerivedData
TEST_FLAGS ?=
LOCAL_SIGN := CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
DMG_SIGN := CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES
RELEASE_APP := $(DERIVED_DATA)/Build/Products/Release/WikiVibe.app
DMG := build/WikiVibe.dmg

.PHONY: gen build release dmg test run clean

gen:
	xcodegen generate
	mkdir -p $(dir $(RESOLVED_PACKAGES))
	cp Package.resolved $(RESOLVED_PACKAGES)

build: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' \
		-derivedDataPath $(DERIVED_DATA) -configuration Debug $(LOCAL_SIGN) build

release: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'generic/platform=macOS' \
		-derivedDataPath $(DERIVED_DATA) -configuration Release ARCHS="arm64 x86_64" \
		ONLY_ACTIVE_ARCH=NO $(DMG_SIGN) build

dmg: release
	codesign --verify --deep --strict "$(RELEASE_APP)"
	@set -eu; \
		stage=$$(mktemp -d "$(DERIVED_DATA)/dmg.XXXXXX"); \
		trap 'rm -rf "$$stage"' EXIT; \
		ditto "$(RELEASE_APP)" "$$stage/WikiVibe.app"; \
		licenses="$$stage/WikiVibe.app/Contents/Resources/DependencyLicenses"; \
		mkdir -p "$$licenses"; \
		ditto LICENSE "$$licenses/WikiVibe-MIT.txt"; \
		for notice in "$(DERIVED_DATA)"/SourcePackages/checkouts/*/LICENSE* "$(DERIVED_DATA)"/SourcePackages/checkouts/*/NOTICE*; do \
			[ -f "$$notice" ] || continue; \
			package=$$(basename "$$(dirname "$$notice")"); \
			mkdir -p "$$licenses/$$package"; \
			ditto "$$notice" "$$licenses/$$package/$$(basename "$$notice")"; \
		done; \
		codesign --force --sign - --options runtime --preserve-metadata=entitlements "$$stage/WikiVibe.app"; \
		codesign --verify --deep --strict "$$stage/WikiVibe.app"; \
		ln -s /Applications "$$stage/Applications"; \
		hdiutil create -ov -volname WikiVibe -fs HFS+ -format UDZO -srcfolder "$$stage" "$(DMG)"
	hdiutil verify "$(DMG)"

test: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' \
		-derivedDataPath $(DERIVED_DATA) -configuration Debug $(LOCAL_SIGN) test $(TEST_FLAGS)

run: build
	open "$(DERIVED_DATA)/Build/Products/Debug/WikiVibe.app"

clean:
	rm -rf build $(PROJECT)
