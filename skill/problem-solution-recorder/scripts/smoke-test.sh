#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$( ( unset CDPATH; cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P ) )"
SKILL_DIR="$( ( unset CDPATH; cd -P -- "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd -P ) )"

usage() {
  cat <<'EOF'
Run an end-to-end smoke test in a temporary directory.

Usage:
  smoke-test.sh
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/psr-smoke.XXXXXX")"
cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT

kb="$tmp/kb"
export PROBLEM_SOLUTION_KB_ROOT="$kb"

"$SKILL_DIR/scripts/init-kb.sh" "$kb"
record_path="$("$SKILL_DIR/scripts/new-record.sh" "Smoke test MCP timeout" --root "$kb" --date 2099-01-01 --tools "bash,codex" --tags "smoke,mcp")"

[[ -f "$record_path" ]] || {
  printf '[fail] new record file missing: %s\n' "$record_path" >&2
  exit 1
}

"$SKILL_DIR/scripts/update-ai-summary-index.sh" "$kb"
"$SKILL_DIR/scripts/doctor-local.sh" "$kb"

[[ -f "$kb/AI_SUMMARY_INDEX.md" ]] || {
  printf '[fail] AI_SUMMARY_INDEX.md missing\n' >&2
  exit 1
}

if ! grep -Fq "2099-01-01" "$kb/AI_SUMMARY_INDEX.md"; then
  printf '[fail] AI_SUMMARY_INDEX.md missing expected date\n' >&2
  exit 1
fi

printf '[ok] smoke test passed\n'
