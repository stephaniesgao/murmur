#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/murmur-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift run --cache-path .build/cache --disable-sandbox -Xswiftc -module-cache-path -Xswiftc "$CLANG_MODULE_CACHE_PATH" MurmurChecks
