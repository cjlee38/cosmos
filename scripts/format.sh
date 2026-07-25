#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
cd "$repo_root/macos"
swiftformat Package.swift Sources Tests Apps/Cosmos/main.swift
