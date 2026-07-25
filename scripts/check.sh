#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
"$repo_root/scripts/build.sh" dev
"$repo_root/scripts/test.sh"
