# Wattson — common tasks.
#
# `make test` needs only a Swift toolchain. Everything else needs Xcode.

SCHEME  := Wattson
PROJECT := Wattson.xcodeproj

.PHONY: help test project build run archive icon lint clean

help:
	@echo "test     — run the WattsonCore unit tests with SwiftPM (no Xcode needed)"
	@echo "project  — generate $(PROJECT) from project.yml (needs xcodegen)"
	@echo "build    — build the app (needs Xcode)"
	@echo "run      — build and launch the app"
	@echo "archive  — build a Release archive for App Store submission"
	@echo "icon     — regenerate the app icon PNGs from Scripts/GenerateAppIcon.swift"

test:
	swift test

project:
	@command -v xcodegen >/dev/null 2>&1 || { echo "xcodegen not found: brew install xcodegen"; exit 1; }
	xcodegen generate

build: project
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug build

run: build
	open "$$(xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -showBuildSettings | awk -F' = ' '/ BUILT_PRODUCTS_DIR/ {print $$2}' | head -1)/Wattson.app"

archive: project
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-archivePath build/Wattson.xcarchive archive

icon:
	swift Scripts/GenerateAppIcon.swift

clean:
	rm -rf build .build $(PROJECT)
