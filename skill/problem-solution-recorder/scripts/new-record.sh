#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$( ( unset CDPATH; cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P ) )"
RESOLVE="$SCRIPT_DIR/resolve-kb-root.sh"

usage() {
  cat <<'EOF'
Create a new problem-solution record skeleton and refresh the AI summary index.

Usage:
  new-record.sh "Issue title" [--root /path/to/kb] [--date YYYY-MM-DD] [--tools "codex,claude"] [--tags "mcp,search"]
EOF
}

title=""
root_arg=""
date_value="$(date +%F)"
tools_value=""
tags_value=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      root_arg="${2:-}"
      shift 2
      ;;
    --date)
      date_value="${2:-}"
      shift 2
      ;;
    --tools)
      tools_value="${2:-}"
      shift 2
      ;;
    --tags)
      tags_value="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$title" ]]; then
        title="$1"
        shift
      else
        printf 'Unexpected argument: %s\n' "$1" >&2
        usage >&2
        exit 2
      fi
      ;;
  esac
done

if [[ -z "$title" ]]; then
  usage >&2
  exit 2
fi

case "$date_value" in
  ????-??-??) ;;
  *)
    printf 'Invalid date, expected YYYY-MM-DD: %s\n' "$date_value" >&2
    exit 2
    ;;
esac

root="$("$RESOLVE" "$root_arg")"
year="${date_value%%-*}"
year_dir="$root/records/$year"
mkdir -p "$year_dir"

slug="$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^[:alnum:]]+/-/g; s/^-+//; s/-+$//' | cut -c 1-48)"
[[ -n "$slug" ]] || slug="issue"

max_seq=0
while IFS= read -r existing; do
  base="$(basename "$existing")"
  seq_part="$(printf '%s\n' "$base" | sed -n -E "s/^${date_value}-([0-9]{3})-.*/\\1/p")"
  [[ -n "$seq_part" ]] || continue
  seq_num=$((10#$seq_part))
  (( seq_num > max_seq )) && max_seq="$seq_num"
done < <(find "$year_dir" -maxdepth 1 -type f -name "${date_value}-*.md" | sort)

next_seq="$(printf '%03d' "$((max_seq + 1))")"
record_rel="records/$year/${date_value}-${next_seq}-${slug}.md"
record_path="$root/$record_rel"

csv_to_yaml_array() {
  local raw="$1"
  local first=1
  local item
  if [[ -z "$raw" ]]; then
    printf '[]'
    return
  fi
  printf '['
  IFS=',' read -r -a parts <<< "$raw"
  for item in "${parts[@]}"; do
    item="$(printf '%s' "$item" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -n "$item" ]] || continue
    item="${item//\\/\\\\}"
    item="${item//\"/\\\"}"
    if [[ "$first" -eq 0 ]]; then
      printf ', '
    fi
    printf '"%s"' "$item"
    first=0
  done
  printf ']'
}

yaml_tools="$(csv_to_yaml_array "$tools_value")"
yaml_tags="$(csv_to_yaml_array "$tags_value")"
safe_title="${title//\\/\\\\}"
safe_title="${safe_title//\"/\\\"}"

cat > "$record_path" <<EOF
---
title: "$safe_title"
date: "$date_value"
status: draft
tools: $yaml_tools
tags: $yaml_tags
---

# $title

## 一句话结论

-

## 原始现象

-

## 环境与关键配置

-

## 排查时间线

-

## 失败尝试

-

## 根因分析

-

## 最终解决方案

-

## 验证方法

-

## 复用经验

-

## 后续事项

-
EOF

if [[ -f "$root/INDEX.md" ]] && ! grep -Fq "$record_rel" "$root/INDEX.md"; then
  printf '| %s | %s | draft | %s | %s | [%s](%s) |\n' "$date_value" "$title" "${tools_value:-"-"}" "${tags_value:-"-"}" "$record_rel" "$record_rel" >> "$root/INDEX.md"
fi

if [[ -x "$SCRIPT_DIR/update-ai-summary-index.sh" ]]; then
  "$SCRIPT_DIR/update-ai-summary-index.sh" "$root" >/dev/null
fi

printf '%s\n' "$record_path"
