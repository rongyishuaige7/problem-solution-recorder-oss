#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$( ( unset CDPATH; cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P ) )"
RESOLVE="$SCRIPT_DIR/resolve-kb-root.sh"
CHECK_KB="$SCRIPT_DIR/check-kb.sh"

root="$("$RESOLVE" "${1:-}")"

failures=0
check_file() {
  local path="$1"
  if [[ -f "$root/$path" ]]; then
    printf '[ok] %s\n' "$path"
  else
    printf '[missing] %s\n' "$path"
    failures=$((failures + 1))
  fi
}

check_dir() {
  local path="$1"
  if [[ -d "$root/$path" ]]; then
    printf '[ok] %s/\n' "$path"
  else
    printf '[missing] %s/\n' "$path"
    failures=$((failures + 1))
  fi
}

printf 'Knowledge base root: %s\n' "$root"
check_file "AI入口.md"
check_file "AI记录提示词.md"
check_file "AI工具记录规则.md"
check_file "INDEX.md"
check_file "AI_SUMMARY_INDEX.md"
check_file "_templates/问题记录模板.md"
check_file "_templates/日报复盘模板.md"
check_file "_templates/周报复盘模板.md"
check_dir "records"
check_dir "patterns"
check_dir "reviews"

if [[ -x "$root/bin/qs" ]]; then
  printf '[ok] bin/qs\n'
  "$root/bin/qs" check >/dev/null || failures=$((failures + 1))
else
  printf '[info] bin/qs not found or not executable; Markdown-only mode is still supported\n'
fi

if [[ -x "$CHECK_KB" ]]; then
  "$CHECK_KB" "$root" --quiet || failures=$((failures + 1))
else
  printf '[missing] scripts/check-kb.sh\n'
  failures=$((failures + 1))
fi

if [[ "$failures" -gt 0 ]]; then
  printf '[fail] %s issue(s) found\n' "$failures" >&2
  exit 1
fi

printf '[ok] local knowledge base is ready\n'
