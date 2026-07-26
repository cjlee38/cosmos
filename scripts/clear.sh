#!/bin/zsh

set -euo pipefail

profile="${1:?Usage: $0 <dev|release>}"

case "$profile" in
    dev)
        bundle_id="io.cjlee.cosmos.debug"
        ;;
    release)
        bundle_id="io.cjlee.cosmos"
        ;;
    *)
        print -u2 "Profile must be dev or release."
        exit 1
        ;;
esac

defaults write "$bundle_id" onboarding.completedVersion -int 0
tccutil reset All "$bundle_id"
