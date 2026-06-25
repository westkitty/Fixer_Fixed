#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -lt 1 ]]; then
  echo "Usage: $0 <path> [path ...]" >&2
  exit 64
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

strings_dump="$work_dir/strings.txt"
text_dump="$work_dir/text.txt"

touch "$strings_dump" "$text_dump"

append_strings() {
  local target="$1"
  while IFS= read -r -d '' file; do
    printf '=== %s ===\n' "$file" >> "$strings_dump"
    strings -a "$file" >> "$strings_dump" 2>/dev/null || true
    printf '\n' >> "$strings_dump"
  done < <(find "$target" -type f -print0)
}

append_text() {
  local target="$1"
  grep -RInaE '.' "$target" >> "$text_dump" 2>/dev/null || true
}

for target in "$@"; do
  if [[ ! -e "$target" ]]; then
    echo "Missing scan target: $target" >&2
    exit 1
  fi
  if [[ -d "$target" ]]; then
    append_strings "$target"
    append_text "$target"
  else
    printf '=== %s ===\n' "$target" >> "$strings_dump"
    strings -a "$target" >> "$strings_dump" 2>/dev/null || true
    printf '\n' >> "$strings_dump"
  fi
done

combined_dump="$work_dir/combined.txt"
cat "$text_dump" "$strings_dump" > "$combined_dump"

forbidden_token_marker='FIXER_BUG_REPORT'"_TOKEN"
forbidden_endpoint_marker='FIXER_BUG_REPORT'"_ENDPOINT"
forbidden_auth_marker='Bea'"rer "
forbidden_remote_marker='rail'"way"
forbidden_bug_path_marker='1132-'"bug-report"

declare -a checks=(
  '/Users/'
  '/private/var/folders/'
  '/private/tmp/'
  '/var/folders/'
  '/home/runner/work/'
  "$forbidden_token_marker"
  "$forbidden_endpoint_marker"
  "$forbidden_auth_marker"
  "$forbidden_remote_marker"
  "$forbidden_bug_path_marker"
  '\b(?:10(?:\.\d{1,3}){3}|192\.168(?:\.\d{1,3}){2}|172\.(?:1[6-9]|2\d|3[0-1])(?:\.\d{1,3}){2}|100\.(?:6[4-9]|[7-9]\d|1\d\d)(?:\.\d{1,3}){2})\b'
  '\b[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[A-Za-z]{2,}\b'
  '\b[a-zA-Z0-9-]+\.ts\.net\b'
  '\b[a-zA-Z0-9-]+\.(?:local|lan|home|internal)\b'
  '\b[0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5}\b'
)

for pattern in "${checks[@]}"; do
  if grep -EIn "$pattern" "$combined_dump" > /dev/null; then
    echo "Leak scan failed for pattern: $pattern" >&2
    grep -EIn "$pattern" "$combined_dump" >&2 || true
    exit 1
  fi
done

echo "Leak scan passed for: $*"
