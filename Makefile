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
	@attempt=0; while pgrep -x Cruftless >/dev/null && [ $$attempt -lt 50 ]; do sleep 0.1; attempt=$$((attempt + 1)); done; if pgrep -x Cruftless >/dev/null; then echo "Cruftless did not quit within 5 seconds." >&2; exit 1; fi
	@open -n "$(APP_PATH)"

APP_PATH = $(shell xcodebuild -project Cruftless/Cruftless.xcodeproj -scheme Cruftless -destination 'platform=macOS' -showBuildSettings | awk -F ' = ' '$$1 == "    TARGET_BUILD_DIR" {print $$2}')/Cruftless.app
