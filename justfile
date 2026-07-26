set shell := ["zsh", "-cu"]

build profile:
    ./scripts/build.sh {{quote(profile)}}

fmt:
    ./scripts/format.sh

lint:
    ./scripts/lint.sh

repl:
    ./scripts/repl.sh

clear profile:
    ./scripts/clear.sh {{quote(profile)}}

run profile:
    ./scripts/run.sh {{quote(profile)}}

fixture:
    ./scripts/fixture.sh

test:
    ./scripts/test.sh

check:
    ./scripts/check.sh

set-version version:
    ./scripts/set-version.sh {{quote(version)}}
