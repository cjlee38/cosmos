#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
signing_args=()
if [[ "${COSMOS_SKIP_CODE_SIGNING:-0}" == "1" ]]; then
    signing_args+=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO)
fi

cd "$repo_root/macos"
swift test
xcodebuild -quiet \
    -project Apps/Cosmos/Cosmos.xcodeproj \
    -scheme Cosmos \
    -configuration Debug \
    -destination "platform=macOS,arch=$(uname -m)" \
    -derivedDataPath .build/xcode \
    "${signing_args[@]}" \
    test
