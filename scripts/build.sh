#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
profile="${1:?Usage: $0 <dev|release>}"

case "$profile" in
    dev)
        configuration="Debug"
        ;;
    release)
        configuration="Release"
        ;;
    *)
        print -u2 "Profile must be dev or release."
        exit 1
        ;;
esac

signing_args=()
if [[ "${COSMOS_SKIP_CODE_SIGNING:-0}" == "1" ]]; then
    signing_args+=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO)
fi

cd "$repo_root/macos"
xcodebuild -quiet \
    -project Apps/Cosmos/Cosmos.xcodeproj \
    -scheme Cosmos \
    -configuration "$configuration" \
    -destination "platform=macOS,arch=$(uname -m)" \
    -derivedDataPath .build/xcode \
    "${signing_args[@]}" \
    build
