#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$( ( unset CDPATH; cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P ) )"
RESOLVE="$SCRIPT_DIR/resolve-kb-root.sh"

usage() {
  cat <<'EOF'
Scan a problem-solution knowledge base for likely secrets.

Usage:
  check-kb.sh [/path/to/kb] [--quiet] [--allow <file>]

Options:
  --allow <file>  Extra ERE patterns; a line matching any pattern is skipped.
                  Blank lines and lines starting with # are ignored.
  --quiet, -q     Only print problems.

Exit codes:
  0  no likely secrets found
  1  potential secrets found
EOF
}

root_arg=""
quiet=0
allow_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quiet|-q)
      quiet=1
      shift
      ;;
    --allow)
      allow_file="${2:-}"
      shift 2
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

if [[ -n "$allow_file" && ! -f "$allow_file" ]]; then
  printf 'Allowlist file not found: %s\n' "$allow_file" >&2
  exit 2
fi

root="$("$RESOLVE" "$root_arg")"
tmp="${TMPDIR:-/tmp}/problem-solution-recorder-kb-secrets.$$"
filtered="${TMPDIR:-/tmp}/problem-solution-recorder-kb-secrets-filtered.$$"
trap 'rm -f "$tmp" "$filtered"' EXIT

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

# 规则要点（避免把普通技术文本当密钥）：
# - sk- 必须位于行首或非标识符边界，避免 "task-polling-..." 这类词误命中；
# - session 规则只认 session_id/session_token/session_key 且要求长值，
#   并排除 "-session:"、"/cross-session:" 这类斜杠命令；
# - 行内含 [REDACTED]、占位词、示例值时跳过。
secret_pattern='(^|[^A-Za-z0-9_-])sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{20,}|Bearer[[:space:]]+[A-Za-z0-9._~+/=-]{30,}|BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY|password[[:space:]]*[:=][[:space:]]*[^[:space:]]{8,}|passwd[[:space:]]*[:=][[:space:]]*[^[:space:]]{8,}|cookie[[:space:]]*[:=][[:space:]]*[^[:space:]]{20,}|(^|[^A-Za-z0-9_/-])session[_-]?(id|token|key)[[:space:]]*[:=][[:space:]]*[A-Za-z0-9._~+/=-]{24,}'

grep -RInE \
  --exclude-dir='.git' \
  --exclude='*.tmp' \
  --exclude='*.generated.tmp' \
  -- "$secret_pattern" \
  "${scan_paths[@]}" > "$tmp" || true

grep -viE 'REDACTED|<[^>]+>|example|your[_-]|xxx|placeholder|dummy|masked|fixture|fake[_-]?key|content[-_]?url|local-?only' "$tmp" > "$filtered" || true

if [[ -n "$allow_file" ]]; then
  grep -vEf <(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^#/d' -e '/^$/d' "$allow_file") "$filtered" > "${filtered}.allow" || true
  mv "${filtered}.allow" "$filtered"
fi

if [[ -s "$filtered" ]]; then
  cat "$filtered" >&2
  printf '[fail] potential secrets found in knowledge base: %s\n' "$root" >&2
  printf 'Hint: redact the value as [REDACTED], or add a narrow ERE line to an allowlist file and pass --allow.\n' >&2
  exit 1
fi

[[ "$quiet" -eq 1 ]] || printf '[ok] no likely secrets found in knowledge base\n'
