#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
config="$repo_root/macos/Apps/Cosmos/Version.xcconfig"
version=$(sed -n 's/^[[:space:]]*MARKETING_VERSION[[:space:]]*=[[:space:]]*//p' "$config")

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    print -u2 "Invalid MARKETING_VERSION in $config"
    exit 1
}

print "$version"
