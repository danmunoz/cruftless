.PHONY: all build test lint fmt run

all: lint test build

build:
	xcodebuild -project Cruftless/Cruftless.xcodeproj -scheme Cruftless -destination 'platform=macOS' build

test:
	swift test --package-path CruftlessCore

lint:
	swiftlint --strict

fmt:
	swiftformat .

run: build
	@pkill -x Cruftless || true
	@open "$(APP_PATH)"

APP_PATH = $(shell xcodebuild -project Cruftless/Cruftless.xcodeproj -scheme Cruftless -destination 'platform=macOS' -showBuildSettings | awk -F ' = ' '$$1 == "    TARGET_BUILD_DIR" {print $$2}')/Cruftless.app
