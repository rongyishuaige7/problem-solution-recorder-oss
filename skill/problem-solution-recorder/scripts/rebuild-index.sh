#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$( ( unset CDPATH; cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P ) )"
RESOLVE="$SCRIPT_DIR/resolve-kb-root.sh"

usage() {
  cat <<'EOF'
Rebuild the human index (INDEX.md) from records/ front matter.

Usage:
  rebuild-index.sh [/path/to/kb] [--dry-run] [--check]

Behavior:
  - Keeps the existing table schema: 6 columns (Date/Title/Status/Tools/Tags/
    Record) or 7 columns (ID/日期/标题/工具/系统/状态/关键根因/记录).
  - Preserves everything before the table header and after the last table row
    (for example a "常用标签" section).
  - Rows are emitted in date-descending order.
  - --dry-run prints the new table instead of writing.
  - --check exits 1 when the file is out of date (no write).
EOF
}

root_arg=""
dry_run=0
check_only=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) dry_run=1; shift ;;
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
records_dir="$root/records"
index="$root/INDEX.md"

[[ -d "$records_dir" ]] || {
  printf 'No records directory: %s\n' "$records_dir" >&2
  exit 1
}

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/psr-index-rebuild.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

files=()
while IFS= read -r f; do
  files+=("$f")
done < <(find "$records_dir" -type f -name '*.md' | sort)

if [[ ${#files[@]} -eq 0 ]]; then
  printf 'No records found under %s\n' "$records_dir" >&2
  exit 1
fi

# 单次 awk：输出 rel<TAB>id<TAB>date<TAB>title<TAB>status<TAB>tools<TAB>tags<TAB>signature
# signature = front matter summary > 根因分析首行 > 一句话结论首行
extract_all() {
  LC_ALL=C awk -v root="$root" '
    function flush_section(   key) {
      if (section == "") return
      key = map[section]
      if (key != "" && out != "" && val[key] == "") val[key] = out
      section = ""; out = ""; count = 0
    }
    function emit_fm(   k, v) {
      for (k in fmv) {
        v = fmv[k]
        gsub(/\t/, " ", v)
        val[k] = v
      }
    }
    function reset() {
      fm = 0; pending = ""; list = ""; fence = 0
      section = ""; out = ""; count = 0
      delete fmv; delete val
    }
    function clean(s) {
      gsub(/^[[:space:]]*([-*]+|[0-9]+\.)[[:space:]]+/, "", s)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      gsub(/[`*]/, "", s)
      return s
    }
    BEGIN {
      reset()
      map["一句话结论"] = "summary"
      map["根因分析"] = "root"
      cap["summary"] = 1; cap["root"] = 1
    }
    FNR == 1 {
      if (NR > 1) {
        flush_section()
        emit_fm()
        rel = prev
        if (index(rel, root "/") == 1) rel = substr(rel, length(root) + 2)
        sig = val["summary"]
        if (sig == "" || sig == "-") sig = val["root"]
        gsub(/\t/, " ", sig)
        printf "%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\n", rel, val["id"], val["date"], val["title"], val["status"], val["tools"], val["tags"], sig
      }
      reset()
      prev = FILENAME
    }
    fm && FNR > 1 && $0 == "---" {
      fm = 0
      if (pending != "") { fmv[pending] = list; pending = ""; list = "" }
      next
    }
    !fm && FNR == 1 && $0 == "---" { fm = 1; next }
    fm {
      if ($0 ~ /^[A-Za-z0-9_-]+:/) {
        if (pending != "") { fmv[pending] = list; pending = ""; list = "" }
        k = $0; sub(/:.*/, "", k)
        v = $0; sub(/^[^:]*:[[:space:]]*/, "", v); gsub(/^"|"$/, "", v)
        if (v ~ /^\[.*\]$/) {
          gsub(/^\[|\]$/, "", v); gsub(/"/, "", v)
          gsub(/[[:space:]]*,[[:space:]]*/, ", ", v)
        }
        if (v == "") { pending = k; list = "" } else { fmv[k] = v }
        next
      }
      if ($0 ~ /^[[:space:]]+-[[:space:]]*/) {
        it = $0; sub(/^[[:space:]]+-[[:space:]]*/, "", it); gsub(/^"|"$/, "", it)
        if (pending != "") list = (list == "" ? it : list ", " it)
        next
      }
      next
    }
    /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]+/ {
      flush_section()
      section = $0
      sub(/^##[[:space:]]+/, "", section)
      sub(/[[:space:]]+$/, "", section)
      next
    }
    {
      if (section == "") next
      key = map[section]
      if (key == "") next
      line = clean($0)
      if (line == "" || line ~ /^\|/) next
      if (count >= cap[key]) next
      out = (out == "" ? line : out "; " line)
      count++
    }
    END {
      flush_section()
      emit_fm()
      rel = prev
      if (index(rel, root "/") == 1) rel = substr(rel, length(root) + 2)
      sig = val["summary"]
      if (sig == "" || sig == "-") sig = val["root"]
      gsub(/\t/, " ", sig)
      printf "%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\n", rel, val["id"], val["date"], val["title"], val["status"], val["tools"], val["tags"], sig
    }
  ' "${files[@]}"
}

rows_raw="$tmp_dir/rows"
extract_all > "$rows_raw"

# 选择列布局
schema=6
if [[ -f "$index" ]] && grep -qE '^\|[[:space:]]*ID[[:space:]]*\|' "$index" && grep -q '关键根因' "$index"; then
  schema=7
fi

rows="$tmp_dir/rows.md"
: > "$rows"

# 按日期倒序（同日期按 id 倒序）
LC_ALL=C sort -t "$(printf '\037')" -k3,3r -k2,2r "$rows_raw" | while IFS=$'\037' read -r rel id date title status tools tags sig; do
  [[ -n "$rel" ]] || continue
  base="${rel##*/}"; base="${base%.md}"
  [[ -n "$date" ]] || date="${base:0:10}"
  if [[ -z "$id" ]]; then
    if [[ "$base" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{3} ]]; then
      id="${BASH_REMATCH[0]}"
    else
      id="${date}-${base}"
    fi
  fi
  [[ -n "$title" ]] || title="$rel"
  [[ -n "$status" ]] || status="unknown"
  [[ -n "$tools" ]] || tools="-"
  [[ -n "$tags" ]] || tags="-"
  [[ -n "$sig" ]] || sig="-"
  if [[ ${#sig} -gt 200 ]]; then sig="${sig:0:197}…"; fi
  title="$(printf '%s' "$title" | sed 's/|/\\|/g')"
  sig="$(printf '%s' "$sig" | sed 's/|/\\|/g')"
  tools="$(printf '%s' "$tools" | sed 's/|/\\|/g')"
  tags="$(printf '%s' "$tags" | sed 's/|/\\|/g')"
  if [[ "$schema" -eq 7 ]]; then
    printf '| %s | %s | %s | %s | %s | %s | [查看](%s) |\n' "$id" "$date" "$title" "$tools" "$status" "$sig" "$rel" >> "$rows"
  else
    printf '| %s | %s | %s | %s | %s | [%s](%s) |\n' "$date" "$title" "$status" "$tools" "$tags" "$rel" "$rel" >> "$rows"
  fi
done

if [[ "$schema" -eq 7 ]]; then
  header='| ID | 日期 | 标题 | 工具/系统 | 状态 | 关键根因 | 记录 |'
else
  header='| Date | Title | Status | Tools | Tags | Record |'
fi
if [[ "$schema" -eq 7 ]]; then
  separator='|---|---|---|---|---|---|---|'
else
  separator='| --- | --- | --- | --- | --- | --- |'
fi

# 保留表头之前与最后一行表格之后的内容
before="$tmp_dir/before"
after="$tmp_dir/after"
: > "$before"
: > "$after"

if [[ -f "$index" ]]; then
  header_line="$(grep -nE '^\|[[:space:]]*(ID|Date)[[:space:]]*\|' "$index" | head -n 1 | cut -d: -f1 || true)"
  if [[ -n "$header_line" ]]; then
    head -n "$(( header_line - 1 ))" "$index" > "$before"
    last_row="$(grep -nE '^\|[[:space:]]*[0-9]{4}-[0-9]{2}-[0-9]{2}' "$index" | tail -n 1 | cut -d: -f1 || true)"
    if [[ -n "$last_row" ]]; then
      total="$(wc -l < "$index" | tr -d ' ')"
      if [[ "$last_row" -lt "$total" ]]; then
        tail -n "+$(( last_row + 1 ))" "$index" > "$after"
      fi
    fi
  fi
fi

new_file="$tmp_dir/INDEX.md"
{
  if [[ -s "$before" ]]; then
    cat "$before"
  else
    printf '# Problem-Solution Index\n\n'
  fi
  printf '%s\n' "$header"
  printf '%s\n' "$separator"
  cat "$rows"
  if [[ -s "$after" ]]; then
    cat "$after"
  fi
} > "$new_file"

row_count="$(grep -c '^| ' "$rows" || true)"

if [[ "$check_only" -eq 1 ]]; then
  if [[ -f "$index" ]] && cmp -s "$new_file" "$index"; then
    printf '[ok] INDEX.md is up to date (%s rows)\n' "$row_count"
    exit 0
  fi
  printf '[stale] INDEX.md differs from records (%s rows expected); run rebuild-index.sh\n' "$row_count" >&2
  exit 1
fi

if [[ "$dry_run" -eq 1 ]]; then
  cat "$new_file"
  exit 0
fi

cp "$new_file" "$index"
printf 'Rebuilt %s (%s rows, %s columns)\n' "$index" "$row_count" "$schema"
