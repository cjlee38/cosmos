set shell := ["zsh", "-cu"]

build:
    swift build

fmt:
    swiftformat Package.swift Sources Tests

lint:
    swiftlint lint
    periphery scan

repl:
    swift run kkaci-cli

dev:
    ./Scripts/build-app debug
    exec ".build/apps/debug/Kkaci Dev.app/Contents/MacOS/Kkaci"

release:
    ./Scripts/build-app release
    exec ".build/apps/release/Kkaci.app/Contents/MacOS/Kkaci"

fixture:
    swift run kkaci-fixture-app

test:
    swift test

check: build test
