set shell := ["zsh", "-cu"]

build profile:
    xcodebuild -quiet -project Apps/Cosmos/Cosmos.xcodeproj -scheme Cosmos -configuration '{{ if profile == "dev" { "Debug" } else if profile == "release" { "Release" } else { error("profile must be dev or release") } }}' -derivedDataPath .build/xcode build

fmt:
    swiftformat Package.swift Sources Tests Apps/Cosmos/main.swift

lint:
    swiftlint lint
    periphery scan --retain-public --index-exclude 'Sources/CosmosApp/**' --index-exclude 'Tests/CosmosAppTests/**' --index-exclude 'Apps/**'
    periphery scan --project Apps/Cosmos/Cosmos.xcodeproj --schemes Cosmos --retain-public

repl:
    swift run cosmos

clear:
    defaults write io.cjlee.cosmos.debug onboarding.completedVersion -int 0
    tccutil reset All io.cjlee.cosmos.debug

run profile: (build profile)
    exec '{{ if profile == "dev" { ".build/xcode/Build/Products/Debug/Cosmos Dev.app/Contents/MacOS/Cosmos Dev" } else if profile == "release" { ".build/xcode/Build/Products/Release/Cosmos.app/Contents/MacOS/Cosmos" } else { error("profile must be dev or release") } }}'

fixture:
    swift run cosmos-fixture-app

test:
    swift test
    xcodebuild -quiet -project Apps/Cosmos/Cosmos.xcodeproj -scheme Cosmos -configuration Debug -derivedDataPath .build/xcode test

check: (build "dev") test
