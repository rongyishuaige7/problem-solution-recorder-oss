#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$( ( unset CDPATH; cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P ) )"
RESOLVE="$SCRIPT_DIR/resolve-kb-root.sh"

usage() {
  cat <<'EOF'
Create a new problem-solution record skeleton and refresh the AI summary index.

Usage:
  new-record.sh "Issue title" [options]

Options:
  --root <path>        Knowledge base root (default: resolved automatically)
  --date YYYY-MM-DD    Record date (default: today)
  --tools "a,b"        tools front matter list
  --tags "a,b"         tags front matter list
  --slug <ascii-slug>  Filename topic (default: slugified title)
  --template <path>    Record template (default: <root>/_templates/问题记录模板.md)
  --no-lock            Skip the knowledge base write lock (tests only)

Writes are serialized with <root>/.psr.lock so concurrent agents cannot
allocate the same sequence number or lose index rows.
EOF
}

title=""
root_arg=""
date_value="$(date +%F)"
tools_value=""
tags_value=""
slug_arg=""
template_arg=""
use_lock=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) root_arg="${2:-}"; shift 2 ;;
    --date) date_value="${2:-}"; shift 2 ;;
    --tools) tools_value="${2:-}"; shift 2 ;;
    --tags) tags_value="${2:-}"; shift 2 ;;
    --slug) slug_arg="${2:-}"; shift 2 ;;
    --template) template_arg="${2:-}"; shift 2 ;;
    --no-lock) use_lock=0; shift ;;
    -h|--help) usage; exit 0 ;;
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

valid_date() {
  local d="$1"
  local out=""
  [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
  out="$(date -d "$d" +%F 2>/dev/null || date -j -f "%Y-%m-%d" "$d" +%F 2>/dev/null || true)"
  [[ "$out" == "$d" ]]
}

if ! valid_date "$date_value"; then
  printf 'Invalid date, expected a real YYYY-MM-DD date: %s\n' "$date_value" >&2
  exit 2
fi

root="$("$RESOLVE" "$root_arg")"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/enumerate.sh"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/ids.sh"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/index.sh"
year="${date_value%%-*}"
year_dir="$root/records/$year"
mkdir -p "$year_dir"

slug=""
if [[ -n "$slug_arg" ]]; then
  slug="$(printf '%s' "$slug_arg" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g' | cut -c 1-48)"
  [[ -n "$slug" ]] || {
    printf 'Slug is empty after normalization: %s\n' "$slug_arg" >&2
    exit 2
  }
else
  slug="$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^[:alnum:]]+/-/g; s/^-+//; s/-+$//' | cut -c 1-48)"
fi
[[ -n "$slug" ]] || slug="issue"

if [[ "$use_lock" -eq 1 ]]; then
  # 路径是运行时拼接的，shellcheck 无法静态解析；锁库随 skill 一起分发。
  # shellcheck source=/dev/null
  . "$SCRIPT_DIR/lib/lock.sh"
  # 先装信号处理再抢锁：在等待锁的过程中被 TERM 也必须终止，而不是继续执行。
  trap 'psr_lock_release "$root"' EXIT
  trap 'psr_lock_release "$root"; exit 130' INT TERM HUP
  psr_lock_acquire "$root" || exit 1
fi

# 序号由共享模块分配：三位起、超过 999 继续递增，避免覆盖同 ID 文件。
record_id="$(psr_next_id "$year_dir" "$date_value")"
record_rel="records/$year/${record_id}-${slug}.md"
record_path="$root/$record_rel"

if [[ -e "$record_path" ]]; then
  printf 'Record already exists: %s\n' "$record_path" >&2
  exit 1
fi

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

front_matter="$(cat <<EOF
---
id: $record_id
title: "$safe_title"
date: "$date_value"
status: draft
severity: medium
tools: $yaml_tools
systems: []
tags: $yaml_tags
summary: ""
---
EOF
)"

builtin_body() {
  cat <<EOF
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
}

# 模板优先级：--template > $root/_templates/问题记录模板.md > 内置骨架
template_path="$template_arg"
if [[ -z "$template_path" ]]; then
  template_path="$root/_templates/问题记录模板.md"
fi

render_body() {
  local body=""
  if [[ -f "$template_path" ]]; then
    body="$(
      awk '
        BEGIN { fm = 0 }
        NR == 1 && $0 == "---" { fm = 1; next }
        fm && $0 == "---" { fm = 0; next }
        fm { next }
        { print }
      ' "$template_path"
    )"
  fi
  if [[ -z "$body" ]]; then
    builtin_body
    return 0
  fi
  if printf '%s\n' "$body" | grep -qE '^#[[:space:]]'; then
    printf '%s\n' "$body" | awk -v t="$title" 'BEGIN { done = 0 } !done && /^#[[:space:]]/ { print "# " t; done = 1; next } { print }'
  else
    printf '# %s\n\n%s\n' "$title" "$body"
  fi
}

body="$(render_body)"

record_tmp="$(mktemp "$year_dir/.${record_id}.XXXXXX")"
{
  printf '%s\n\n' "$front_matter"
  printf '%s\n' "$body"
} > "$record_tmp"
mv "$record_tmp" "$record_path"

index_path="$root/INDEX.md"

if [[ ! -f "$index_path" ]]; then
  {
    printf '# Problem-Solution Index\n\n'
    printf '| Date | Title | Status | Tools | Tags | Record |\n'
    printf '| --- | --- | --- | --- | --- | --- |\n'
  } > "$index_path"
fi

if ! grep -Fq "$record_rel" "$index_path"; then
  if ! grep -qE '^\|[[:space:]]*(ID|Date)[[:space:]]*\|' "$index_path"; then
    printf 'INDEX.md has no recognizable table header (| ID | ... or | Date | ...); index row not written.\n' >&2
  else
    index_schema="$(psr_index_schema "$index_path")"
    index_row="$(psr_index_row "$index_schema" "$record_id" "$date_value" "$title" "${tools_value:--}" "${tags_value:--}" draft "待补充" "$record_rel")"
    psr_index_insert "$index_path" "$index_row" "$record_id"
  fi
fi

# 先报告已落盘的路径：后续派生维护失败时，调用方仍能指出记录位置。
printf '%s\n' "$record_path"

if [[ -x "$SCRIPT_DIR/update-ai-summary-index.sh" ]]; then
  if ! "$SCRIPT_DIR/update-ai-summary-index.sh" "$root" --no-lock >/dev/null 2>&1; then
    printf '[warn] record saved, but the summary index could not be refreshed.\n' >&2
    printf 'Recover: %s/update-ai-summary-index.sh "%s"\n' "$SCRIPT_DIR" "$root" >&2
    exit 3
  fi
fi
