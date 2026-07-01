set shell := ["zsh", "-cu"]

build:
    swift build

run:
    swift run kkaci

app:
    swift run kkaci-app

test:
    swift test

check: build test
