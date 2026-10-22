#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$( ( unset CDPATH; cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P ) )"
RESOLVE="$SCRIPT_DIR/resolve-kb-root.sh"
CHECK_KB="$SCRIPT_DIR/check-kb.sh"

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

# ---- 一致性检查：索引与记录必须互相对得上 ----

records_found=0
if [[ -d "$root/records" ]]; then
  records_found="$(find "$root/records" -type f -name '*.md' | wc -l | tr -d ' ')"
fi
printf '[info] records: %s\n' "$records_found"

if [[ "$records_found" -gt 0 ]]; then
  # 1) 重复 ID
  dup_ids="$(find "$root/records" -type f -name '*.md' | sed -E 's|.*/||' | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{3}' | sort | uniq -d || true)"
  if [[ -n "$dup_ids" ]]; then
    printf '[fail] duplicate record IDs:\n'
    printf '%s\n' "$dup_ids" | sed 's/^/  - /'
    failures=$((failures + 1))
  else
    printf '[ok] record IDs are unique\n'
  fi

  # 2) 索引断链
  index_path="$root/INDEX.md"
  if [[ -f "$index_path" ]]; then
    broken="$(grep -oE '\]\([^)]+\.md\)' "$index_path" 2>/dev/null | sed -E 's/^\]\((.*)\)$/\1/' | while IFS= read -r rel; do
      [[ -f "$root/$rel" ]] || printf '%s\n' "$rel"
    done || true)"
    if [[ -n "$broken" ]]; then
      printf '[fail] INDEX.md links to missing records:\n'
      printf '%s\n' "$broken" | sed 's/^/  - /'
      failures=$((failures + 1))
    else
      printf '[ok] INDEX.md links resolve\n'
    fi

    # 3) 记录未入索引
    missing_rows=""
    while IFS= read -r file; do
      rel="${file#"$root"/}"
      if ! grep -Fq "$rel" "$index_path"; then
        missing_rows="${missing_rows}${rel}
"
      fi
    done < <(find "$root/records" -type f -name '*.md' | sort)
    if [[ -n "$missing_rows" ]]; then
      printf '[warn] records missing from INDEX.md:\n'
      printf '%s' "$missing_rows" | sed '/^$/d; s/^/  - /'
      warnings=$((warnings + 1))
    else
      printf '[ok] every record has an INDEX.md row\n'
    fi

    # 4) 状态不一致（只比对英文枚举；中文状态视为人工描述，跳过）
    mismatches="$(awk -F'|' -v root="$root" '
      function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
      /^\|[[:space:]]*ID[[:space:]]*\|/ { schema = 7 }
      /^\|[[:space:]]*Date[[:space:]]*\|/ { schema = 6 }
      /^\|[[:space:]]*[0-9]{4}-[0-9]{2}-[0-9]{2}/ {
        for (i = 1; i <= NF; i++) $i = trim($i)
        if (schema == 7) { status = $6; link = $8 } else { status = $4; link = $7 }
        if (status !~ /^(draft|solved|workaround|investigating|unresolved)$/) next
        if (!match(link, /\(([^)]+)\)/)) next
        rel = substr(link, RSTART + 1, RLENGTH - 2)
        cmd = "grep -m1 \"^status:\" \"" root "/" rel "\" 2>/dev/null"
        cmd | getline line
        close(cmd)
        sub(/^status:[[:space:]]*/, "", line)
        gsub(/^"|"$/, "", line)
        if (line != "" && line != status) printf "  - %s: INDEX=%s record=%s\n", rel, status, line
      }
    ' "$index_path" 2>/dev/null || true)"
    if [[ -n "$mismatches" ]]; then
      printf '[warn] INDEX.md status differs from record front matter:\n'
      printf '%s\n' "$mismatches"
      warnings=$((warnings + 1))
    else
      printf '[ok] INDEX.md status matches records\n'
    fi
  fi

  # 5) 仍是占位内容的记录
  rec_files=()
  while IFS= read -r f; do
    rec_files+=("$f")
  done < <(find "$root/records" -type f -name '*.md' | sort)
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
