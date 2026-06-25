#!/usr/bin/env bash
set -euo pipefail

default_zip="$HOME/Desktop/1132.Fixer-v1.6.4-local-safe-ci-unsigned.zip"
zip_path="${1:-$default_zip}"

if [[ ! -f "$zip_path" ]]; then
  echo "ZIP not found: $zip_path" >&2
  exit 1
fi

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

echo "SHA-256:"
shasum -a 256 "$zip_path"

echo "Extracting with ditto..."
ditto -x -k "$zip_path" "$temp_dir"

app_path="$(find "$temp_dir" -maxdepth 1 -type d -name '*.app' -print -quit)"
if [[ -z "$app_path" ]]; then
  echo "No app bundle found in $zip_path" >&2
  exit 1
fi

binary_path="$app_path/Contents/MacOS/1132 Fixer"
if [[ -f "$binary_path" ]]; then
  chmod +x "$binary_path"
fi
xattr -dr com.apple.quarantine "$app_path" 2>/dev/null || true

target_path="/Applications/$(basename "$app_path")"
if cp -R "$app_path" "/Applications/"; then
  echo "Copied app to $target_path"
  open "$target_path"
else
  echo "Could not copy app into /Applications. Copy it manually from:"
  echo "$app_path"
  open "$app_path"
fi
