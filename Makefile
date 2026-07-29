.PHONY: project build test clean

project:
	xcodegen generate

build: project
	xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build

test: project
	xcodebuild -project Lumina.xcodeproj -scheme Lumina -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test

clean:
	swift package clean
