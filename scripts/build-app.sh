#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/murmur-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift build --cache-path .build/cache -c "$configuration" --disable-sandbox -Xswiftc -module-cache-path -Xswiftc "${TMPDIR:-/tmp}/murmur-module-cache"
mkdir -p build
stage="$(mktemp -d "$PWD/build/.murmur-stage.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/Murmur.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp ".build/$configuration/Murmur" "$app/Contents/MacOS/Murmur"
cp Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
if [[ -n "${MURMUR_SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --entitlements Entitlements.plist --sign "$MURMUR_SIGN_IDENTITY" "$app"
else
  # Ad-hoc signatures default to a requirement tied to this exact binary, so macOS forgets
  # Accessibility/Input Monitoring grants after every rebuild. Pin the requirement to the
  # bundle identifier so permissions survive rebuilds of this development build.
  codesign --force --entitlements Entitlements.plist --sign - -r='designated => identifier "com.steph.murmur"' "$app"
fi
codesign --verify --deep --strict "$app"
# Rename whole bundles: never truncate an executable that may be mapped by a running app.
if [[ -d build/Murmur.app ]]; then mv build/Murmur.app "$stage/previous.app"; fi
mv "$app" build/Murmur.app
printf '%s\n' "Built $PWD/build/Murmur.app"
