set shell := ["zsh", "-cu"]

build:
    swift build

fmt:
    swiftformat Package.swift Sources Tests Apps/Kkaci/main.swift

lint:
    swiftlint lint
    periphery scan

repl:
    swift run kkaci-cli

dev:
    xcodebuild -quiet -project Apps/Kkaci/Kkaci.xcodeproj -scheme Kkaci -configuration Debug -derivedDataPath .build/xcode build
    exec ".build/xcode/Build/Products/Debug/Kkaci Dev.app/Contents/MacOS/Kkaci Dev"

release:
    xcodebuild -quiet -project Apps/Kkaci/Kkaci.xcodeproj -scheme Kkaci -configuration Release -derivedDataPath .build/xcode build
    exec ".build/xcode/Build/Products/Release/Kkaci.app/Contents/MacOS/Kkaci"

fixture:
    swift run kkaci-fixture-app

test:
    swift test
    xcodebuild -quiet -project Apps/Kkaci/Kkaci.xcodeproj -scheme Kkaci -configuration Debug -derivedDataPath .build/xcode test

check: build test
