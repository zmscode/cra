#!/usr/bin/env bash
# Records the SDK the binary was really built with in its LC_BUILD_VERSION.
#
#   scripts/stamp-sdk.sh <mach-o>
#
# SwiftPM's newer build backend links through `clang --sysroot`, so ld never learns the
# SDK version and writes the deployment target there instead (sdk 14.0 on a 27 SDK).
# AppKit reads that field to decide the app's look: an app "linked on" 14.0 gets the
# pre-macOS 26 window controls (flat 12 pt traffic lights 24 pt apart) instead of the
# current ones (14 pt glass buttons 23 pt apart). Run it before codesigning.
set -euo pipefail

bin="$1"
sdk="$(xcrun --sdk macosx --show-sdk-version)"
info="$(otool -l "$bin" | grep -A4 LC_BUILD_VERSION)"
minos="$(awk '/minos/ { print $2; exit }' <<<"$info")"
recorded="$(awk '/ sdk / { print $2; exit }' <<<"$info")"
[ "$recorded" = "$sdk" ] && exit 0
xcrun vtool -set-build-version macos "$minos" "$sdk" -replace -output "$bin.stamped" "$bin" 2>/dev/null
mv "$bin.stamped" "$bin"
