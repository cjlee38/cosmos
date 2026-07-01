set shell := ["zsh", "-cu"]

build:
    swift build

run:
    swift run kkaci

test:
    swift test

check: build test
