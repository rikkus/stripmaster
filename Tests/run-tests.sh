#!/usr/bin/env bash
# Compile and run the functional suite.
#
# The model, document state, persistence and connectivity code is deliberately
# free of SwiftUI, so this needs nothing from Xcode beyond the Swift toolchain:
# no test host, no simulator, no scheme. The UI smoke tests live in
# StripmasterUITests and run through Xcode.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

sources=(
  "$root"/Stripmaster/Model/*.swift
  "$root"/Tests/*.swift
)

swiftc -swift-version 6 -o "$out/functional-tests" "${sources[@]}"
"$out/functional-tests"
