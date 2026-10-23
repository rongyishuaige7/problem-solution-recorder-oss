#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$( ( unset CDPATH; cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P ) )"
RESOLVE="$SCRIPT_DIR/resolve-kb-root.sh"
PARSER="$SCRIPT_DIR/lib/record-fields.awk"

usage() {
  cat <<'EOF'
Rebuild the human index (INDEX.md) from records/ front matter.

Usage:
  rebuild-index.sh [/path/to/kb] [--dry-run|--preview] [--check] [--overwrite-handwritten]

Behavior:
  - Keeps the existing table schema: 6 columns (Date/Title/Status/Tools/Tags/
    Record) or 7 columns (ID/日期/标题/工具/系统/状态/关键根因/记录).
  - Preserves everything before the table header and after the last table row.
  - Rows are emitted in date-descending order.
  - Takes the knowledge base write lock (<root>/.psr.lock).
  - A 7-column index keeps the existing title/tools/status/关键根因 cells by ID
    (only date and link are refreshed); pass --overwrite-handwritten to rebuild
    every cell from the records.
  - --dry-run / --preview prints a diff instead of writing.
  - --check exits 1 when the file is out of date (no write).
  - --allow-empty permits rebuilding an empty index when records/ has no
    entries (otherwise existing rows would be dropped silently).
  - Writes are skipped when the result is byte-identical.
EOF
}

root_arg=""
dry_run=0
check_only=0
overwrite_handwritten=0
allow_empty=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run|--preview) dry_run=1; shift ;;
    --check) check_only=1; shift ;;
    --overwrite-handwritten) overwrite_handwritten=1; shift ;;
    --allow-empty) allow_empty=1; shift ;;
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
[[ -f "$PARSER" ]] || {
  printf 'Missing record parser: %s\n' "$PARSER" >&2
  exit 1
}

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/psr-index-rebuild.XXXXXX")"

# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/enumerate.sh"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/index.sh"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/lock.sh"
trap 'psr_lock_release "$root"; rm -rf "$tmp_dir"' EXIT
trap 'psr_lock_release "$root"; rm -rf "$tmp_dir"; exit 130' INT TERM HUP
psr_lock_acquire "$root" || exit 1

files=()
if ! psr_list_records "$records_dir" "$tmp_dir/files"; then
  printf 'Could not enumerate %s; index left unchanged.\n' "$records_dir" >&2
  exit 1
fi
while IFS= read -r f; do
  files+=("$f")
done < "$tmp_dir/files"

empty_library=0
if [[ ${#files[@]} -eq 0 ]]; then
  existing_rows=0
  if [[ -f "$index" ]]; then
    existing_rows="$(grep -cE '^\|[[:space:]]*[0-9]{4}-[0-9]{2}-[0-9]{2}' "$index" || true)"
  fi
  if [[ "$existing_rows" -gt 0 && "$allow_empty" -eq 0 ]]; then
    printf '[fail] 没有记录，但 INDEX.md 仍有 %s 行；重建会清空它们。\n' "$existing_rows" >&2
    printf '确认后重跑: rebuild-index.sh "%s" --allow-empty\n' "$root" >&2
    exit 1
  fi
  printf '[warn] 没有记录，将重建为空索引\n' >&2
  empty_library=1
fi

stream="$tmp_dir/stream"
awk_err="$tmp_dir/awk.err"

if [[ "$empty_library" -eq 1 ]]; then
  : > "$stream"
else
  set +e
  LC_ALL=C awk -v root="$root" -v maxlines=4 -f "$PARSER" "${files[@]}" > "$stream" 2> "$awk_err"
  awk_rc=$?
  set -e

  if [[ "$awk_rc" -ne 0 ]]; then
    cat "$awk_err" >&2
    printf '[fail] could not read every record (awk exit %s); %s left unchanged.\n' "$awk_rc" "$index" >&2
    exit 1
  fi
  parsed_records="$(grep -c '^@R' "$stream" || true)"
  expected_records=0
  for f in "${files[@]}"; do
    [[ -s "$f" ]] && expected_records=$(( expected_records + 1 ))
  done
  if [[ "$parsed_records" -ne "$expected_records" ]]; then
    cat "$awk_err" >&2
    printf '[fail] parsed %s of %s non-empty records; %s left unchanged.\n' "$parsed_records" "$expected_records" "$index" >&2
    exit 1
  fi
  if [[ "$expected_records" -ne "${#files[@]}" ]]; then
    printf '[warn] skipped %s empty record file(s)\n' "$(( ${#files[@]} - expected_records ))" >&2
  fi
fi

# 选择列布局
schema=6
if [[ -f "$index" ]] && grep -qE '^\|[[:space:]]*ID[[:space:]]*\|' "$index" && grep -q '关键根因' "$index"; then
  schema=7
fi

rows_raw="$tmp_dir/rows.tsv"
: > "$rows_raw"
cur_rel=""
reset_fields() {
  id=""; date=""; title=""; status=""; tools=""; tags=""; sig=""; fm_sig=""
}
reset_fields
emit_row() {
  [[ -n "$cur_rel" ]] || return 0
  local base="${cur_rel##*/}"
  base="${base%.md}"
  [[ -n "$date" ]] || date="${base:0:10}"
  if [[ -z "$id" ]]; then
    if [[ "$base" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{3} ]]; then
      id="${BASH_REMATCH[0]}"
    else
      id="${date}-${base}"
    fi
  fi
  [[ -n "$title" ]] || title="$cur_rel"
  [[ -n "$status" ]] || status="unknown"
  [[ -n "$tools" ]] || tools="-"
  [[ -n "$tags" ]] || tags="-"
  local signature="$fm_sig"
  [[ -n "$signature" ]] || signature="$sig"
  [[ -n "$signature" ]] || signature="-"
  printf '%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\n' \
    "$cur_rel" "$id" "$date" "$title" "$status" "$tools" "$tags" "$signature" >> "$rows_raw"
}

while IFS=$'\t' read -r tag field value; do
  case "$tag" in
    '@R')
      emit_row
      cur_rel="$field"
      reset_fields
      ;;
    '@W')
      printf '[warn] %s: unsupported YAML for %s; treated as empty\n' "$field" "$value" >&2
      ;;
    '@F')
      case "$field" in
        id) id="$value" ;;
        title) title="$value" ;;
        date) date="$value" ;;
        status) status="$value" ;;
        tools) tools="$value" ;;
        tags) tags="$value" ;;
        signature) sig="$value" ;;
        fm_summary) fm_sig="$value" ;;
      esac
      ;;
  esac
done < "$stream"
emit_row

# 7 列索引的“关键根因”常是手写内容：默认按 ID 保留，避免重建把它冲掉。
if [[ "$schema" -eq 7 && "$overwrite_handwritten" -eq 0 && -f "$index" ]]; then
  psr_index_rows "$index" > "$tmp_dir/existing.tsv"
  if [[ -s "$tmp_dir/existing.tsv" ]]; then
    LC_ALL=C awk -F'\037' -v OFS='\037' -v keepfile="$tmp_dir/existing.tsv" '
      BEGIN {
        while ((getline line < keepfile) > 0) {
          n = split(line, p, "\037")
          if (p[1] == "") continue
          title[p[1]] = p[3]; tools[p[1]] = p[4]; status[p[1]] = p[5]; root[p[1]] = p[6]
        }
        close(keepfile)
      }
      {
        if ($2 in title) {
          # 已有行：标题/工具/状态/关键根因保留人工版本，只刷新日期与链接。
          if (title[$2] != "") $4 = title[$2]
          if (tools[$2] != "") $6 = tools[$2]
          if (status[$2] != "") $5 = status[$2]
          if (root[$2] != "" && root[$2] != "待补充" && root[$2] != "-") $8 = root[$2]
        }
        print
      }
    ' "$rows_raw" > "$tmp_dir/rows.merged"
    mv "$tmp_dir/rows.merged" "$rows_raw"
  fi
fi

rows="$tmp_dir/rows.md"
: > "$rows"

LC_ALL=C sort -t "$(printf '\037')" -k3,3r -k2,2r "$rows_raw" | while IFS=$'\037' read -r rel id date title status tools tags sig; do
  [[ -n "$rel" ]] || continue
  [[ -n "$title" ]] || title="$rel"
  [[ -n "$status" ]] || status="unknown"
  [[ -n "$tools" ]] || tools="-"
  [[ -n "$tags" ]] || tags="-"
  [[ -n "$sig" ]] || sig="-"
  if [[ ${#sig} -gt 200 ]]; then sig="${sig:0:197}…"; fi
  # 纯 bash 转义，避免每行 4 次 sed 子进程。
  title="${title//\\/\\\\}"; title="${title//|/\\|}"
  sig="${sig//\\/\\\\}"; sig="${sig//|/\\|}"
  tools="${tools//\\/\\\\}"; tools="${tools//|/\\|}"
  tags="${tags//\\/\\\\}"; tags="${tags//|/\\|}"
  if [[ "$schema" -eq 7 ]]; then
    printf '| %s | %s | %s | %s | %s | %s | [查看](%s) |\n' "$id" "$date" "$title" "$tools" "$status" "$sig" "$rel" >> "$rows"
  else
    printf '| %s | %s | %s | %s | %s | [%s](%s) |\n' "$date" "$title" "$status" "$tools" "$tags" "$rel" "$rel" >> "$rows"
  fi
done

if [[ "$schema" -eq 7 ]]; then
  header='| ID | 日期 | 标题 | 工具/系统 | 状态 | 关键根因 | 记录 |'
  separator='|---|---|---|---|---|---|---|'
else
  header='| Date | Title | Status | Tools | Tags | Record |'
  separator='| --- | --- | --- | --- | --- | --- |'
fi

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
  if [[ -f "$index" ]]; then
    if cmp -s "$new_file" "$index"; then
      printf '[ok] no changes (%s rows)\n' "$row_count"
    else
      diff -u "$index" "$new_file" || true
    fi
  else
    cat "$new_file"
  fi
  exit 0
fi

if [[ -f "$index" ]] && cmp -s "$new_file" "$index"; then
  printf 'Unchanged: %s (%s rows)\n' "$index" "$row_count"
  exit 0
fi

cp "$new_file" "$index"
printf 'Rebuilt %s (%s rows, %s columns)\n' "$index" "$row_count" "$schema"
