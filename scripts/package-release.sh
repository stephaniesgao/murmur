#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

app_path="${1:-build/Murmur.app}"
out_dir="${2:-build/release}"
download_url="${3:-${MURMUR_DOWNLOAD_URL:-}}"
notes="${MURMUR_RELEASE_NOTES:-}"

if [[ ! -d "$app_path" ]]; then
  printf 'App bundle not found: %s\n' "$app_path" >&2
  exit 1
fi
if [[ -z "$download_url" ]]; then
  printf 'Usage: %s <app_path> <output_dir> <download_url>\n' "$0" >&2
  exit 1
fi

mkdir -p "$out_dir"
zip_path="$out_dir/Murmur.zip"
rm -f "$zip_path"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"

sha256="$(/usr/bin/shasum -a 256 "$zip_path" | awk '{print $1}')"
plist="$app_path/Contents/Info.plist"
version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist")"
build="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$plist")"
commit="$(/usr/libexec/PlistBuddy -c "Print :MurmurCommitSHA" "$plist" 2>/dev/null || true)"
published_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

/usr/bin/python3 - "$out_dir/update.json" "$version" "$build" "$commit" "$download_url" "$sha256" "$notes" "$published_at" <<'PY'
import json, sys
out_path, version, build, commit, download_url, sha256, notes, published_at = sys.argv[1:]
manifest = {
    "version": version,
    "build": int(build),
    "downloadURL": download_url,
    "sha256": sha256,
    "publishedAt": published_at,
}
if commit:
    manifest["commit"] = commit
if notes:
    manifest["notes"] = notes
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(manifest, f, indent=2)
    f.write("\n")
PY

printf 'Packaged %s and %s/update.json (v%s build %s, sha256 %s)\n' "$zip_path" "$out_dir" "$version" "$build" "$sha256"
