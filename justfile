set shell := ["zsh", "-cu"]

build profile:
    xcodebuild -quiet -project Apps/Kkaci/Kkaci.xcodeproj -scheme Kkaci -configuration '{{ if profile == "dev" { "Debug" } else if profile == "release" { "Release" } else { error("profile must be dev or release") } }}' -derivedDataPath .build/xcode build

fmt:
    swiftformat Package.swift Sources Tests Apps/Kkaci/main.swift

lint:
    swiftlint lint
    periphery scan --retain-public --index-exclude 'Sources/KkaciApp/**' --index-exclude 'Tests/KkaciAppTests/**' --index-exclude 'Apps/**'
    periphery scan --project Apps/Kkaci/Kkaci.xcodeproj --schemes Kkaci --retain-public

repl:
    swift run kkaci

clear:
    defaults write dev.kkaci.app.debug onboarding.completedVersion -int 0
    tccutil reset All dev.kkaci.app.debug

run profile: (build profile)
    exec '{{ if profile == "dev" { ".build/xcode/Build/Products/Debug/Kkaci Dev.app/Contents/MacOS/Kkaci Dev" } else if profile == "release" { ".build/xcode/Build/Products/Release/Kkaci.app/Contents/MacOS/Kkaci" } else { error("profile must be dev or release") } }}'

fixture:
    swift run kkaci-fixture-app

test:
    swift test
    xcodebuild -quiet -project Apps/Kkaci/Kkaci.xcodeproj -scheme Kkaci -configuration Debug -derivedDataPath .build/xcode test

check: (build "dev") test
