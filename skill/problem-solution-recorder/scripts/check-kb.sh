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
  --allow <file>  Extra ERE patterns; a matched secret value matching any
                  pattern is skipped. Blank lines and lines starting with #
                  are ignored. Invalid patterns are a usage error.
  --quiet, -q     Only print problems.

Exit codes:
  0  scan completed, no likely secrets found
  1  potential secrets found
  2  scan could not complete (unreadable path, invalid allowlist, grep error)

Diagnostics never print the full secret value: only the first and last four
characters are shown.
EOF
}

root_arg=""
quiet=0
allow_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quiet|-q) quiet=1; shift ;;
    --allow) allow_file="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
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

# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/secrets.sh"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/psr-secrets.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

files_list="$tmp_dir/files"
matches="$tmp_dir/matches"
errors="$tmp_dir/errors"
findings="$tmp_dir/findings"
: > "$files_list"
: > "$findings"

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
# - 只按“匹配到的值”判断例外，不按整行或路径判断。
secret_pattern="$PSR_SECRET_PATTERN"

# 2) 校验白名单正则（非法正则必须报错，不能被 || true 吞掉）。
if [[ -n "$allow_file" ]]; then
  while IFS= read -r raw; do
    pat="$(printf '%s' "$raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -z "$pat" || "$pat" == \#* ]] && continue
    : > "$tmp_dir/empty"
    set +e
    grep -qE -- "$pat" "$tmp_dir/empty" 2>/dev/null
    pat_rc=$?
    set -e
    if [[ "$pat_rc" -gt 1 ]]; then
      printf 'Invalid allowlist pattern: %s\n' "$pat" >&2
      exit 2
    fi
    PSR_SECRET_ALLOW+=("$pat")
  done < "$allow_file"
fi

# 1) 先取文件清单：rc=1 表示没有匹配，rc>1 表示扫描失败（权限、I/O 等）。
set +e
grep -RIlE --exclude-dir='.git' --exclude='*.tmp' -- "$secret_pattern" "${scan_paths[@]}" > "$files_list" 2>"$errors"
grep_rc=$?
set -e

if [[ "$grep_rc" -gt 1 ]]; then
  cat "$errors" >&2
  printf '[fail] secret scan could not complete (grep exit %s); result is unknown, not clean.\n' "$grep_rc" >&2
  exit 2
fi

if [[ "$grep_rc" -eq 1 || ! -s "$files_list" ]]; then
  [[ "$quiet" -eq 1 ]] || printf '[ok] no likely secrets found in knowledge base\n'
  exit 0
fi

found=0
while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  set +e
  grep -nEo -- "$secret_pattern" "$file" > "$matches" 2>>"$errors"
  file_rc=$?
  set -e
  if [[ "$file_rc" -gt 1 ]]; then
    cat "$errors" >&2
    printf '[fail] secret scan could not complete while reading %s; result is unknown, not clean.\n' "$file" >&2
    exit 2
  fi
  [[ -s "$matches" ]] || continue
  while IFS= read -r line; do
    lineno="${line%%:*}"
    value="${line#*:}"
    # 去掉规则里捕获的前导边界字符
    value="$(printf '%s' "$value" | sed -E 's/^[^A-Za-z0-9_]+//')"
    [[ -n "$value" ]] || continue
    if psr_secret_is_benign "$value"; then
      continue
    fi
    printf '%s:%s: %s\n' "$file" "$lineno" "$(psr_secret_mask "$value")" >> "$findings"
    found=$(( found + 1 ))
  done < "$matches"
done < "$files_list"

if [[ "$found" -gt 0 ]]; then
  cat "$findings" >&2
  printf '[fail] %s potential secret(s) found in knowledge base: %s\n' "$found" "$root" >&2
  printf 'Hint: redact the value as [REDACTED], or add a narrow ERE line to an allowlist file and pass --allow.\n' >&2
  exit 1
fi

[[ "$quiet" -eq 1 ]] || printf '[ok] no likely secrets found in knowledge base\n'
