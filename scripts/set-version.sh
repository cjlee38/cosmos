#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
config="$repo_root/macos/Apps/Cosmos/Version.xcconfig"
version="${1:-}"

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    print -u2 "Usage: just set-version <major.minor.patch>"
    exit 1
}

previous=$("$repo_root/scripts/version.sh")

{
    print "MARKETING_VERSION = $version"
    print "CURRENT_PROJECT_VERSION = 1"
} >"$config"

print "Updated MARKETING_VERSION: $previous -> $version"
