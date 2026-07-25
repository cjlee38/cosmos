#!/bin/zsh

set -euo pipefail

defaults write io.cjlee.cosmos.debug onboarding.completedVersion -int 0
tccutil reset All io.cjlee.cosmos.debug
