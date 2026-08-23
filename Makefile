.PHONY: project build test clean

project:
	xcodegen generate

build: project
	xcodebuild -project Hikari.xcodeproj -scheme Hikari -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build

test: project
	xcodebuild -project Hikari.xcodeproj -scheme Hikari -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test

clean:
	swift package clean
