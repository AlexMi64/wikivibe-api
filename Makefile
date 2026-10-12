# Native macOS development only. Distribution/signing/update-feed contracts
# are not configured; no publish, deploy, notarize or payment targets exist.
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

.PHONY: gen build test run clean

gen:
	xcodegen generate
	mkdir -p $(dir $(RESOLVED_PACKAGES))
	cp Package.resolved $(RESOLVED_PACKAGES)

build: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' \
		-derivedDataPath $(DERIVED_DATA) -configuration Debug $(LOCAL_SIGN) build

test: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' \
		-derivedDataPath $(DERIVED_DATA) -configuration Debug $(LOCAL_SIGN) test $(TEST_FLAGS)

run: build
	open "$(DERIVED_DATA)/Build/Products/Debug/WikiVibe.app"

clean:
	rm -rf build $(PROJECT)
