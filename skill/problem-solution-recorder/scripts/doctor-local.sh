#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$( ( unset CDPATH; cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P ) )"
RESOLVE="$SCRIPT_DIR/resolve-kb-root.sh"
CHECK_KB="$SCRIPT_DIR/check-kb.sh"
PARSER="$SCRIPT_DIR/lib/record-fields.awk"

root="$("$RESOLVE" "${1:-}")"

failures=0
warnings=0

check_file() {
  local path="$1"
  if [[ -f "$root/$path" ]]; then
    printf '[ok] %s\n' "$path"
  else
    printf '[missing] %s\n' "$path"
    failures=$((failures + 1))
  fi
}

check_optional_file() {
  local path="$1"
  if [[ -f "$root/$path" ]]; then
    printf '[ok] %s\n' "$path"
  else
    printf '[warn] %s (optional)\n' "$path"
    warnings=$((warnings + 1))
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
check_optional_file "_templates/日报复盘模板.md"
check_optional_file "_templates/周报复盘模板.md"
check_dir "records"
check_dir "patterns"
check_dir "reviews"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/psr-doctor.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/enumerate.sh"

records_file="$tmp_dir/records.tsv"
: > "$records_file"

rec_files=()
if [[ -d "$root/records" ]]; then
  if psr_list_records "$root/records" "$tmp_dir/record-files"; then
    while IFS= read -r f; do
      rec_files+=("$f")
    done < "$tmp_dir/record-files"
  else
    printf '[fail] could not enumerate records; results below are incomplete\n'
    failures=$((failures + 1))
  fi
fi

records_found="${#rec_files[@]}"
printf '[info] records: %s\n' "$records_found"

if [[ "$records_found" -gt 0 ]]; then
  if [[ -f "$PARSER" ]]; then
    LC_ALL=C awk -v root="$root" -v maxlines=0 -f "$PARSER" "${rec_files[@]}" > "$tmp_dir/stream" 2>/dev/null || true
    cur_rel=""
    cur_id=""
    cur_status=""
    emit_record_row() {
      [[ -n "$cur_rel" ]] || return 0
      printf '%s\037%s\037%s\037%s\n' "${cur_id:-$cur_rel}" "$cur_rel" "${cur_status:-unknown}" "${cur_date:-}" >> "$records_file"
    }
    yaml_warnings=0
    while IFS=$'\t' read -r tag field value; do
      case "$tag" in
        '@R') emit_record_row; cur_rel="$field"; cur_id=""; cur_status=""; cur_date="" ;;
        '@W') yaml_warnings=$(( yaml_warnings + 1 )) ;;
        '@F')
          case "$field" in
            id) cur_id="$value" ;;
            date) cur_date="$value" ;;
            status) cur_status="$value" ;;
          esac
          ;;
      esac
    done < "$tmp_dir/stream"
    emit_record_row
    if [[ "$yaml_warnings" -gt 0 ]]; then
      printf '[warn] %s record field(s) use unsupported YAML (block scalars or nested maps)\n' "$yaml_warnings"
      warnings=$((warnings + 1))
    fi
  else
    printf '[warn] record parser missing: %s\n' "$PARSER"
    warnings=$((warnings + 1))
  fi

  # 1) 重复 ID（完整比较，不再截断到三位序号）
  dup_ids="$(awk -F'\037' '{ print $1 }' "$records_file" | sort | uniq -d || true)"
  if [[ -n "$dup_ids" ]]; then
    printf '[fail] duplicate record IDs:\n'
    printf '%s\n' "$dup_ids" | sed 's/^/  - /'
    failures=$((failures + 1))
  else
    printf '[ok] record IDs are unique\n'
  fi
fi

index_path="$root/INDEX.md"
if [[ -f "$index_path" ]]; then
  # 2) 索引断链：即使 records/ 为空也要检查（索引可能指向已删除的记录）
  broken="$(awk '
    {
      row = $0
      gsub(/\\\|/, "\001", row)
      if (row !~ /^\|/) next
      while (match(row, /\]\(([^)]+\.md)\)/)) {
        print substr(row, RSTART + 2, RLENGTH - 3)
        row = substr(row, RSTART + RLENGTH)
      }
    }
  ' "$index_path" | while IFS= read -r rel; do
    [[ -f "$root/$rel" ]] || printf '%s\n' "$rel"
  done || true)"
  if [[ -n "$broken" ]]; then
    printf '[fail] INDEX.md links to missing records:\n'
    printf '%s\n' "$broken" | sed 's/^/  - /'
    failures=$((failures + 1))
  else
    printf '[ok] INDEX.md links resolve\n'
  fi

  if [[ "$records_found" -gt 0 ]]; then
    # 3) 记录未入索引
    missing_rows=""
    for file in ${rec_files[@]+"${rec_files[@]}"}; do
      rel="${file#"$root"/}"
      if ! grep -Fq "$rel" "$index_path"; then
        missing_rows="${missing_rows}${rel}
"
      fi
    done
    if [[ -n "$missing_rows" ]]; then
      printf '[warn] records missing from INDEX.md:\n'
      printf '%s' "$missing_rows" | sed '/^$/d; s/^/  - /'
      warnings=$((warnings + 1))
    else
      printf '[ok] every record has an INDEX.md row\n'
    fi

    # 4) 状态不一致：转义竖线先替换成哨兵，避免表格列错位
    mismatches="$(awk -v recs="$records_file" '
      function machine(cell) {
        if (cell ~ /^solved/ || cell ~ /^已解决/) return "solved"
        if (cell ~ /^workaround/ || cell ~ /^临时方案/ || cell ~ /^变通/) return "workaround"
        if (cell ~ /^investigating/ || cell ~ /^调查中/ || cell ~ /^实施中/) return "investigating"
        if (cell ~ /^unresolved/ || cell ~ /^未解决/) return "unresolved"
        if (cell ~ /^draft/ || cell ~ /^草稿/) return "draft"
        return ""
      }
      BEGIN {
        while ((getline line < recs) > 0) {
          n = split(line, p, "\037")
          status[p[2]] = p[3]
          rdate[p[2]] = p[4]
        }
        close(recs)
      }
      {
        row = $0
        gsub(/\\\|/, "\001", row)
        if (row ~ /^\|[[:space:]]*ID[[:space:]]*\|/) { schema = 7; next }
        if (row ~ /^\|[[:space:]]*Date[[:space:]]*\|/) { schema = 6; next }
        if (row !~ /^\|[[:space:]]*[0-9]{4}-[0-9]{2}-[0-9]{2}/) next
        n = split(row, f, "|")
        if (schema == 7) { row_date = f[3]; row_status = f[6]; link = f[8] } else { row_date = f[2]; row_status = f[4]; link = f[7] }
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", row_status)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", row_date)
        mapped = machine(row_status)
        if (mapped == "") next
        if (!match(link, /\(([^)]+)\)/)) next
        rel = substr(link, RSTART + 1, RLENGTH - 2)
        if (rel in status && status[rel] != mapped) {
          printf "  - %s: INDEX=%s record=%s\n", rel, row_status, status[rel]
        }
        if (rel in rdate && rdate[rel] != "" && row_date != rdate[rel]) {
          printf "  - %s: INDEX date=%s record=%s\n", rel, row_date, rdate[rel]
        }
      }
    ' "$index_path" 2>/dev/null || true)"
    if [[ -n "$mismatches" ]]; then
      printf '[warn] INDEX.md differs from record front matter (status/date):\n'
      printf '%s\n' "$mismatches"
      warnings=$((warnings + 1))
    else
      printf '[ok] INDEX.md status and date match records\n'
    fi

    # 5) front matter 缺少 date（页面与索引会回退到文件名，容易掩盖问题）
    missing_date=""
    for f in "${rec_files[@]}"; do
      LC_ALL=C awk '
        NR == 1 && $0 == "---" { fm = 1; next }
        fm && $0 == "---" { exit }
        fm && /^date:[[:space:]]*"?[0-9]{4}-[0-9]{2}-[0-9]{2}/ { found = 1; exit }
        END { exit(found ? 0 : 1) }
      ' "$f" || missing_date="${missing_date}${f}
"
    done
    if [[ -n "$missing_date" ]]; then
      printf '[warn] records missing a date field:\n'
      printf '%s' "$missing_date" | sed '/^$/d; s|^|  - |'
      warnings=$((warnings + 1))
    else
      printf '[ok] every record has a date field\n'
    fi

    # 6) 仍是占位内容的记录
    placeholders="$(LC_ALL=C awk '
      FNR == 1 { section = 0 }
      /^##[[:space:]]+一句话结论/ { section = 1; empty = 1; next }
      section && /^##[[:space:]]/ { if (empty) print FILENAME; section = 0 }
      section {
        line = $0
        gsub(/^[[:space:]-]+/, "", line)
        if (line != "" && line != "待填写。" && line !~ /^用 1 到 3 句话/) empty = 0
      }
      END { if (section && empty) print FILENAME }
    ' ${rec_files[@]+"${rec_files[@]}"} 2>/dev/null || true)"
    if [[ -n "$placeholders" ]]; then
      printf '[warn] records still have a placeholder conclusion:\n'
      printf '%s\n' "$placeholders" | sed "s|$root/||; s/^/  - /"
      warnings=$((warnings + 1))
    else
      printf '[ok] no placeholder conclusions\n'
    fi
  fi
fi

# 5) 残留写锁与回收 guard：存在时写入会被阻塞，doctor 必须报告。
doctor_mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || printf '0'
}
lock_path="$root/.psr.lock"
guard_path="$root/.psr.lock.guard"
if [[ -d "$lock_path" || -d "$guard_path" ]]; then
  lock_pid=""
  [[ -f "$lock_path/pid" ]] && lock_pid="$(cat "$lock_path/pid" 2>/dev/null || true)"
  guard_pid=""
  [[ -f "$guard_path/pid" ]] && guard_pid="$(cat "$guard_path/pid" 2>/dev/null || true)"
  lock_alive=0
  guard_alive=0
  lock_unknown=0
  guard_unknown=0
  [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null && lock_alive=1
  [[ -n "$guard_pid" ]] && kill -0 "$guard_pid" 2>/dev/null && guard_alive=1

  # 目录刚建、pid 还没写入的窗口：无法证明已死，按“进行中”处理。
  now_ts="$(date +%s)"
  if [[ -d "$lock_path" && -z "$lock_pid" ]]; then
    lock_age=$(( now_ts - $(doctor_mtime "$lock_path") ))
    [[ "$lock_age" -le 60 ]] && lock_unknown=1
  fi
  if [[ -d "$guard_path" && -z "$guard_pid" ]]; then
    guard_age=$(( now_ts - $(doctor_mtime "$guard_path") ))
    [[ "$guard_age" -le 60 ]] && guard_unknown=1
  fi

  if [[ "$lock_alive" -eq 1 || "$guard_alive" -eq 1 || "$lock_unknown" -eq 1 || "$guard_unknown" -eq 1 ]]; then
    if [[ "$lock_alive" -eq 1 || "$guard_alive" -eq 1 ]]; then
      printf '[warn] a writer appears to be running (lock pid=%s, guard pid=%s)\n' "${lock_pid:-none}" "${guard_pid:-none}"
    else
      printf '[warn] a lock or guard is initializing (no owner written yet)\n'
    fi
    warnings=$((warnings + 1))
  else
    printf '[fail] leftover write lock blocks writers:\n'
    [[ -d "$lock_path" ]] && printf '  - %s\n' "$lock_path"
    [[ -d "$guard_path" ]] && printf '  - %s\n' "$guard_path"
    printf '  recovery: rm -rf "%s" "%s"\n' "$lock_path" "$guard_path"
    failures=$((failures + 1))
  fi
else
  printf '[ok] no leftover write lock\n'
fi

if [[ -x "$root/bin/web-check" ]]; then
  if command -v node >/dev/null 2>&1; then
    if web_out="$("$root/bin/web-check" 2>&1)"; then
      printf '[ok] bin/web-check\n'
    else
      printf '[fail] bin/web-check\n'
      printf '%s\n' "$web_out" | sed -n '1,12p' | sed 's/^/  /'
      printf '  recovery: node web/generate-data.js && bin/web-check\n'
      failures=$((failures + 1))
    fi
  else
    printf '[info] node not found; web data consistency not verified\n'
  fi
else
  printf '[info] bin/web-check not found (optional web dashboard check)\n'
fi

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
  printf '[fail] %s error(s), %s warning(s)\n' "$failures" "$warnings" >&2
  exit 1
fi

if [[ "$warnings" -gt 0 ]]; then
  printf '[ok] local knowledge base is usable (%s warning(s))\n' "$warnings"
  exit 0
fi

printf '[ok] local knowledge base is ready\n'
