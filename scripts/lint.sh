#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
cd "$repo_root/macos"

signing_args=()
if [[ "${COSMOS_SKIP_CODE_SIGNING:-0}" == "1" ]]; then
    signing_args+=(-- CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO)
fi

swiftlint lint
periphery scan \
    --retain-public \
    --index-exclude 'Sources/CosmosApp/**' \
    --index-exclude 'Tests/CosmosAppTests/**' \
    --index-exclude 'Apps/**'
periphery scan \
    --project Apps/Cosmos/Cosmos.xcodeproj \
    --schemes Cosmos \
    --retain-public \
    "${signing_args[@]}"
