#!/usr/bin/env bash
# Builds Just for macOS on a Mac with Xcode and Flutter installed.
# Output: releases/<version>/Just-<version>-macOS.zip and its SHA-256.
set -euo pipefail
cd "$(dirname "$0")/../app"
version=$(sed -nE 's/^version: ([0-9.]+).*/\1/p' pubspec.yaml)
flutter pub get
flutter test
flutter build macos --release
out=../releases/$version
mkdir -p "$out"
# ditto keeps the bundle's symlinks and extended attributes intact.
ditto -c -k --keepParent build/macos/Build/Products/Release/Just.app "$out/Just-$version-macOS.zip"
(cd "$out" && shasum -a 256 "Just-$version-macOS.zip" > SHA256SUMS-macOS.txt)
echo "Готово: $out/Just-$version-macOS.zip"
