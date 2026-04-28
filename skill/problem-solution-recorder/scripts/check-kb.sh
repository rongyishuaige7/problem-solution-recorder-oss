#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$( ( unset CDPATH; cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P ) )"
RESOLVE="$SCRIPT_DIR/resolve-kb-root.sh"

usage() {
  cat <<'EOF'
Scan a problem-solution knowledge base for likely secrets.

Usage:
  check-kb.sh [/path/to/kb] [--quiet]
EOF
}

root_arg=""
quiet=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quiet|-q)
      quiet=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$root_arg" ]]; then
        root_arg="$1"
        shift
      else
        printf 'Unexpected argument: %s\n' "$1" >&2
        usage >&2
        exit 2
      fi
      ;;
  esac
done

root="$("$RESOLVE" "$root_arg")"
tmp="${TMPDIR:-/tmp}/problem-solution-recorder-kb-secrets.$$"
trap 'rm -f "$tmp"' EXIT

: > "$tmp"

scan_paths=()
for path in \
  "$root/AI_SUMMARY_INDEX.md" \
  "$root/INDEX.md" \
  "$root/records" \
  "$root/patterns" \
  "$root/reviews"; do
  [[ -e "$path" ]] && scan_paths+=("$path")
done

if [[ "${#scan_paths[@]}" -eq 0 ]]; then
  [[ "$quiet" -eq 1 ]] || printf '[ok] no knowledge base files to scan\n'
  exit 0
fi

grep -RInE \
  --exclude-dir='.git' \
  --exclude='*.tmp' \
  --exclude='*.generated.tmp' \
  '(sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{20,}|Authorization:[[:space:]]*Bearer[[:space:]]+[A-Za-z0-9._~+/=-]{10,}|BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY|password[[:space:]]*[:=][[:space:]]*[^[:space:]]{6,}|passwd[[:space:]]*[:=][[:space:]]*[^[:space:]]{6,}|cookie[[:space:]]*[:=][[:space:]]*[^[:space:]]{10,}|session[_-]?(id|token)?[[:space:]]*[:=][[:space:]]*[^[:space:]]{10,})' \
  "${scan_paths[@]}" > "$tmp" || true

if [[ -s "$tmp" ]]; then
  cat "$tmp" >&2
  printf '[fail] potential secrets found in knowledge base: %s\n' "$root" >&2
  exit 1
fi

[[ "$quiet" -eq 1 ]] || printf '[ok] no likely secrets found in knowledge base\n'
