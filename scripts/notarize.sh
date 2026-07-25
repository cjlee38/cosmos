#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
cd "$repo_root/macos"

version="${1:?Usage: $0 <version>}"
output_dmg="dist/Cosmos-$version.dmg"
work_dir=".build/distribution/notarization-$$"
dmg="$work_dir/Cosmos-$version.dmg"

trap 'rm -rf "$work_dir"' EXIT

"$repo_root/scripts/package.sh"
actual_version=$(/usr/libexec/PlistBuddy \
    -c "Print :CFBundleShortVersionString" \
    ".build/distribution/export/Cosmos.app/Contents/Info.plist")
[[ "$actual_version" == "$version" ]] || {
    print -u2 "Requested version $version does not match packaged version $actual_version."
    exit 1
}
[[ -f "$output_dmg" ]] || {
    print -u2 "The packaged version does not match $version."
    exit 1
}

mkdir -p "$work_dir"
ditto "$output_dmg" "$dmg"
hdiutil verify "$dmg"
codesign --verify --strict --verbose=2 "$dmg"

print "DMG: $output_dmg"
print "Bundle ID: io.cjlee.cosmos"
print "Team ID: UKA4NU5898"
read "answer?Submit this DMG to Apple for notarization? Type 'yes': "
[[ "$answer" == "yes" ]] || {
    print "Cancelled."
    exit 1
}

xcrun notarytool submit \
    "$dmg" \
    --keychain-profile cosmos-notary \
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
