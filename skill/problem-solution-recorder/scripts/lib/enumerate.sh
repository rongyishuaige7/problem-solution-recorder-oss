# shellcheck shell=bash
# Safe record enumeration shared by every writer.
#
# Usage:
#   psr_list_records <records-dir> <outfile>
#
# Writes sorted .md paths (one per line) to <outfile>. Returns:
#   0  complete listing (the file may legitimately be empty)
#   2  enumeration failed; <outfile> holds partial data and MUST NOT be used
#
# Why not `while read < <(find ...)`: a failure inside process substitution is
# invisible to the caller, so an unreadable directory looked like an empty
# knowledge base and the derived index was rewritten without those records.

psr_list_records() {
  local dir="$1"
  local out="$2"
  local err="$out.err"

  : > "$out"
  : > "$err"

  if ! find "$dir" -type f -name '*.md' -print > "$out" 2> "$err"; then
    [[ -s "$err" ]] && cat "$err" >&2
    return 2
  fi

  # find 可能在返回 0 的同时打印警告；任何 stderr 都视为不完整。
  if [[ -s "$err" ]]; then
    cat "$err" >&2
    return 2
  fi

  LC_ALL=C sort -o "$out" "$out" || return 2
  return 0
}
