set shell := ["zsh", "-cu"]

build profile:
    cd macos && xcodebuild -quiet -project Apps/Cosmos/Cosmos.xcodeproj -scheme Cosmos -configuration '{{ if profile == "dev" { "Debug" } else if profile == "release" { "Release" } else { error("profile must be dev or release") } }}' -derivedDataPath .build/xcode build

fmt:
    cd macos && swiftformat Package.swift Sources Tests Apps/Cosmos/main.swift

lint:
    cd macos && swiftlint lint
    cd macos && periphery scan --retain-public --index-exclude 'Sources/CosmosApp/**' --index-exclude 'Tests/CosmosAppTests/**' --index-exclude 'Apps/**'
    cd macos && periphery scan --project Apps/Cosmos/Cosmos.xcodeproj --schemes Cosmos --retain-public

repl:
    cd macos && swift run cosmos

clear:
    defaults write io.cjlee.cosmos.debug onboarding.completedVersion -int 0
    tccutil reset All io.cjlee.cosmos.debug

run profile: (build profile)
    exec '{{ if profile == "dev" { "macos/.build/xcode/Build/Products/Debug/Cosmos Dev.app/Contents/MacOS/Cosmos Dev" } else if profile == "release" { "macos/.build/xcode/Build/Products/Release/Cosmos.app/Contents/MacOS/Cosmos" } else { error("profile must be dev or release") } }}'

fixture:
    cd macos && swift run cosmos-fixture-app

test:
    cd macos && swift test
    cd macos && xcodebuild -quiet -project Apps/Cosmos/Cosmos.xcodeproj -scheme Cosmos -configuration Debug -derivedDataPath .build/xcode test

check: (build "dev") test

package:
    ./scripts/package.sh

notarize version:
    ./scripts/notarize.sh {{quote(version)}}
