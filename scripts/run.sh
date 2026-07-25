#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
profile="${1:?Usage: $0 <dev|release>}"

"$repo_root/scripts/build.sh" "$profile"

case "$profile" in
    dev)
        executable="$repo_root/macos/.build/xcode/Build/Products/Debug/Cosmos Dev.app/Contents/MacOS/Cosmos Dev"
        ;;
    release)
        executable="$repo_root/macos/.build/xcode/Build/Products/Release/Cosmos.app/Contents/MacOS/Cosmos"
        ;;
    *)
        print -u2 "Profile must be dev or release."
        exit 1
        ;;
esac

exec "$executable"
