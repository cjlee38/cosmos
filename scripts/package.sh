#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
cd "$repo_root/macos"

archive=".build/distribution/Cosmos.xcarchive"
export_dir=".build/distribution/export"
staging=".build/distribution/dmg"

rm -rf "$archive" "$export_dir" "$staging"
mkdir -p "$export_dir" "$staging" dist

xcodebuild -quiet \
    -project Apps/Cosmos/Cosmos.xcodeproj \
    -scheme Cosmos \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$archive" \
    archive

xcodebuild -quiet \
    -exportArchive \
    -archivePath "$archive" \
    -exportPath "$export_dir" \
    -exportOptionsPlist Distribution/ExportOptions.plist

app="$export_dir/Cosmos.app"
info="$app/Contents/Info.plist"
executable="$app/Contents/MacOS/Cosmos"
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$info")
dmg="dist/Cosmos-$version.dmg"

[[ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$info")" == "io.cjlee.cosmos" ]]
codesign --verify --deep --strict --verbose=2 "$app"
signature=$(codesign -dvvv "$app" 2>&1)
[[ "$signature" == *"Authority=Developer ID Application: CHANJOO LEE (UKA4NU5898)"* ]]
[[ "$signature" == *"Runtime Version="* ]]
archs=$(lipo -archs "$executable")
[[ "$archs" == *arm64* && "$archs" == *x86_64* ]] || {
    print -u2 "Expected a Universal binary, found: $archs"
    exit 1
}

ditto "$app" "$staging/Cosmos.app"
ln -s /Applications "$staging/Applications"
rm -f "$dmg"
hdiutil create \
    -volname Cosmos \
    -srcfolder "$staging" \
    -ov \
    -format UDZO \
    "$dmg"

codesign \
    --force \
    --sign "Developer ID Application: CHANJOO LEE (UKA4NU5898)" \
    --timestamp \
    --identifier io.cjlee.cosmos.dmg \
    "$dmg"
codesign --verify --strict --verbose=2 "$dmg"

print "Created $dmg"
print "Architectures: $archs"
