set shell := ["zsh", "-cu"]

build:
    swift build

fmt:
    swiftformat Package.swift Sources Tests

lint:
    swiftlint lint
    periphery scan

run:
    swift run kkaci

app:
    swift run kkaci-app

fixture:
    swift run kkaci-fixture-app

test:
    swift test

check: build test
