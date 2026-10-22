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

escape_md_cell() {
  local value="$1"
  value="$(printf '%s' "$value" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//')"
  value="${value//\\/\\\\}"
  value="${value//|/\\|}"
  printf '%s' "$value"
}

yaml_tools="$(csv_to_yaml_array "$tools_value")"
yaml_tags="$(csv_to_yaml_array "$tags_value")"
safe_title="${title//\\/\\\\}"
safe_title="${safe_title//\"/\\\"}"

cat > "$record_path" <<EOF
---
id: ${date_value}-${next_seq}
title: "$safe_title"
date: "$date_value"
status: draft
severity: medium
tools: $yaml_tools
systems: []
tags: $yaml_tags
summary: ""
---

# $title

## 一句话结论

用 1 到 3 句话写最终结论。先说明根因，再说明解决方案。

## 背景

- 使用场景：
- 所在项目或目录：
- 相关工具版本：
- 相关服务或账号：

## 原始现象

用户看到的现象、报错、卡住位置或关键日志。

\`\`\`text
粘贴关键输出，注意隐藏密钥。
\`\`\`

## 影响范围

- 影响哪些命令或功能：
- 不影响哪些功能：
- 是否阻塞工作：

## 环境与关键配置

\`\`\`text
OS:
Shell:
Tool versions:
Important env:
Important config files:
\`\`\`

## 排查时间线

1. 做了什么检查：
   - 观察：
   - 结论：
2. 做了什么验证：
   - 观察：
   - 结论：

## 失败尝试

| 尝试 | 结果 | 为什么没解决 |
|---|---|---|
|  |  |  |

## 根因分析

- 表层原因：
- 直接原因：
- 深层原因：
- 为什么之前没有发现：

## 最终解决方案

写清楚最终改了什么、为什么这样改。

\`\`\`bash
# 关键命令
\`\`\`

## 修改的文件

| 文件 | 作用 |
|---|---|
|  |  |

## 验证方法

\`\`\`bash
# 验证命令
\`\`\`

期望输出：

\`\`\`text
关键成功输出
\`\`\`

## 复用经验

- 下次看到类似现象，先检查什么：
- 哪些日志最有价值：
- 哪些假设被证明是错的：

## 后续事项

- [ ] 是否需要清理临时文件
- [ ] 是否需要重置密钥
- [ ] 是否需要写自动化检查

## AI 摘要提示

后续让 AI 总结这条记录时，可以关注：

- 问题链路
- 根因分层
- 最终配置
- 可复用排查顺序
EOF

index_path="$root/INDEX.md"
record_id="${date_value}-${next_seq}"

if [[ ! -f "$index_path" ]]; then
  {
    printf '# Problem-Solution Index\n\n'
    printf '| Date | Title | Status | Tools | Tags | Record |\n'
    printf '| --- | --- | --- | --- | --- | --- |\n'
  } > "$index_path"
fi

if ! grep -Fq "$record_rel" "$index_path"; then
  index_title="$(escape_md_cell "$title")"
  index_tools="$(escape_md_cell "${tools_value:-"-"}")"
  index_tags="$(escape_md_cell "${tags_value:-"-"}")"
  header_line="$(grep -m1 -E '^\|[[:space:]]*(ID|Date)[[:space:]]*\|' "$index_path" || true)"

  # 按已有表头选择列布局：7 列（ID/日期/标题/工具/状态/关键根因/记录）或 6 列（Date/Title/Status/Tools/Tags/Record）。
  if [[ "$header_line" == *"关键根因"* ]]; then
    index_row="| $record_id | $date_value | $index_title | $index_tools | draft | 待补充 | [查看]($record_rel) |"
  elif [[ -n "$header_line" ]]; then
    index_row="| $date_value | $index_title | draft | $index_tools | $index_tags | [$record_rel]($record_rel) |"
  else
    printf 'INDEX.md 中找不到表格表头（| ID | ... 或 | Date | ...），未写入索引行。\n' >&2
    index_row=""
  fi

  if [[ -n "$index_row" ]]; then
    insert_after="$(awk -v key="$record_id" '
      /^\|[[:space:]]*[0-9]{4}-[0-9]{2}-[0-9]{2}/ {
        line = $0
        sub(/^\|[[:space:]]*/, "", line)
        sub(/[[:space:]]*\|.*/, "", line)
        if (!found && line < key) { print NR - 1; found = 1; exit }
        if (!first) { first = NR }
        last = NR
      }
      END {
        if (found) exit
        if (first) print first - 1
        else print 0
      }
    ' "$index_path")"

    if [[ -z "$insert_after" || "$insert_after" -eq 0 ]]; then
      insert_after="$(grep -nE '^\|[-:| ]+\|$' "$index_path" | head -n 1 | cut -d: -f1 || true)"
    fi
    if [[ -z "$insert_after" ]]; then
      printf '%s\n' "$index_row" >> "$index_path"
    else
      index_tmp="$(mktemp "${TMPDIR:-/tmp}/psr-index.XXXXXX")"
      # 用环境变量传行内容：awk -v 会把 \| 解释成 |，破坏 Markdown 转义。
      PSR_INDEX_ROW="$index_row" awk -v n="$insert_after" 'NR == n { print; print ENVIRON["PSR_INDEX_ROW"]; next } { print }' "$index_path" > "$index_tmp"
      mv "$index_tmp" "$index_path"
    fi
  fi
fi

if [[ -x "$SCRIPT_DIR/update-ai-summary-index.sh" ]]; then
  "$SCRIPT_DIR/update-ai-summary-index.sh" "$root" >/dev/null
fi

printf '%s\n' "$record_path"
