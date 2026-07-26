#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
cd "$repo_root"

version="${1:?Usage: $0 <version>}"
tag="v$version"
dmg="macos/dist/Cosmos-$version.dmg"
checksum="$dmg.sha256"
release_commit=$(git rev-parse HEAD)

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    print -u2 "Version must use the form X.Y.Z."
    exit 1
}
[[ -f "$dmg" ]] || {
    print -u2 "Release artifact not found: $dmg"
    exit 1
}
(
    cd "${dmg:h}"
    shasum -a 256 "${dmg:t}" >"${checksum:t}"
)

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

if git show-ref --verify --quiet "refs/tags/$tag"; then
    [[ "$(git cat-file -t "$tag")" == "tag" &&
        "$(git rev-list -n 1 "$tag")" == "$release_commit" ]] || {
        print -u2 "$tag already exists but is not the expected annotated tag."
        exit 1
    }
else
    git tag --annotate "$tag" "$release_commit" --message "Cosmos $version"
fi
git push origin "$tag"

if existing_release=$(gh release view "$tag" --json isDraft --jq .isDraft 2>/dev/null); then
    [[ "$existing_release" == "true" ]] || {
        print -u2 "$tag already has a published GitHub Release."
        exit 1
    }
else
    gh release create "$tag" \
        --verify-tag \
        --title "Cosmos $version" \
        --generate-notes \
        --draft
fi

gh release upload "$tag" "$dmg" "$checksum" --clobber

print "Draft release created for $tag."
