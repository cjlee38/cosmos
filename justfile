set shell := ["zsh", "-cu"]

build:
    swift build

run:
    swift run kkaci

app:
    swift run kkaci-app

fixture:
    swift run kkaci-fixture-app

test:
    swift test

check: build test
