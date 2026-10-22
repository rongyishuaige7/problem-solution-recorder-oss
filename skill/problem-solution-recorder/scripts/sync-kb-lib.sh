#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$( ( unset CDPATH; cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P ) )"
RESOLVE="$SCRIPT_DIR/resolve-kb-root.sh"

usage() {
  cat <<'EOF'
Copy the canonical record parser and lock library into a knowledge base.

Usage:
  sync-kb-lib.sh [/path/to/kb] [--check]

Writes:
  <kb>/bin/lib/record-fields.awk
  <kb>/bin/lib/lock.sh
  <kb>/bin/lib/ids.sh
  <kb>/bin/lib/index.sh
  <kb>/bin/lib/secrets.sh

The knowledge base CLI (bin/qs) and the skill scripts must use the same files;
--check reports drift without writing and exits 1 when they differ.
EOF
}

root_arg=""
check_only=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) check_only=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      if [[ -z "$root_arg" ]]; then
        root_arg="$1"; shift
      else
        printf 'Unexpected argument: %s\n' "$1" >&2
        usage >&2
        exit 2
      fi
      ;;
  esac
done

root="$("$RESOLVE" "$root_arg")"
dest="$root/bin/lib"

drift=0
for file in record-fields.awk lock.sh ids.sh index.sh secrets.sh; do
  src="$SCRIPT_DIR/lib/$file"
  [[ -f "$src" ]] || {
    printf 'Missing skill library: %s\n' "$src" >&2
    exit 1
  }
  if [[ "$check_only" -eq 1 ]]; then
    if [[ ! -f "$dest/$file" ]]; then
      printf '[missing] %s\n' "$dest/$file" >&2
      drift=1
    elif ! cmp -s "$src" "$dest/$file"; then
      printf '[drift] %s differs from %s\n' "$dest/$file" "$src" >&2
      drift=1
    else
      printf '[ok] %s\n' "$dest/$file"
    fi
    continue
  fi
  mkdir -p "$dest"
  cp "$src" "$dest/$file"
  printf '[synced] %s\n' "$dest/$file"
done

if [[ "$check_only" -eq 1 && "$drift" -ne 0 ]]; then
  printf 'Run sync-kb-lib.sh without --check to update the knowledge base copies.\n' >&2
  exit 1
fi

if [[ "$check_only" -eq 0 ]]; then
  printf 'Parser/lock version: %s\n' "$(shasum -a 256 "$SCRIPT_DIR/lib/record-fields.awk" "$SCRIPT_DIR/lib/lock.sh" 2>/dev/null | awk '{print $1}' | tr '\n' ' ')"
fi
