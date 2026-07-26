#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
cd "$repo_root/macos"

confirmed="${1:-}"
work_dir=".build/distribution/notarization-$$"

trap 'rm -rf "$work_dir"' EXIT

"$repo_root/scripts/package.sh"
version=$(/usr/libexec/PlistBuddy \
    -c "Print :CFBundleShortVersionString" \
    ".build/distribution/export/Cosmos.app/Contents/Info.plist")
output_dmg="dist/Cosmos-$version.dmg"
dmg="$work_dir/Cosmos-$version.dmg"
[[ -f "$output_dmg" ]] || {
    print -u2 "Packaged DMG not found: $output_dmg"
    exit 1
}

mkdir -p "$work_dir"
ditto "$output_dmg" "$dmg"
hdiutil verify "$dmg"
codesign --verify --strict --verbose=2 "$dmg"

print "DMG: $output_dmg"
print "Bundle ID: io.cjlee.cosmos"
print "Team ID: UKA4NU5898"
if [[ "$confirmed" != "--yes" ]]; then
    read "answer?Submit this DMG to Apple for notarization? Type 'yes': "
    [[ "$answer" == "yes" ]] || {
        print "Cancelled."
        exit 1
    }
fi

notary_credentials=()
if [[ -n "${APPLE_APP_PASSWORD:-}" ]]; then
    : "${APPLE_ID:?APPLE_ID is required when APPLE_APP_PASSWORD is set}"
    : "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required when APPLE_APP_PASSWORD is set}"
    notary_credentials=(
        --apple-id "$APPLE_ID"
        --password "$APPLE_APP_PASSWORD"
        --team-id "$APPLE_TEAM_ID"
    )
else
    notary_credentials=(--keychain-profile cosmos-notary)
fi

xcrun notarytool submit \
    "$dmg" \
    "${notary_credentials[@]}" \
    --wait
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl --assess \
    --type open \
    --context context:primary-signature \
    --verbose=2 \
    "$dmg"

ditto "$dmg" "$output_dmg"
print "Notarized and verified $output_dmg"
