#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$( ( unset CDPATH; cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P ) )"
SKILL_DIR="$( ( unset CDPATH; cd -P -- "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd -P ) )"

usage() {
  cat <<'EOF'
Run an end-to-end smoke test in a temporary directory.

Usage:
  smoke-test.sh
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/psr-smoke.XXXXXX")"
cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT

fail() {
  printf '[fail] %s\n' "$*" >&2
  exit 1
}

kb="$tmp/kb"
export PROBLEM_SOLUTION_KB_ROOT="$kb"

"$SKILL_DIR/scripts/init-kb.sh" "$kb"
record_path="$("$SKILL_DIR/scripts/new-record.sh" "Smoke test MCP | timeout" --root "$kb" --date 2099-01-01 --tools "bash,codex" --tags "smoke,mcp")"

[[ -f "$record_path" ]] || fail "new record file missing: $record_path"

"$SKILL_DIR/scripts/update-ai-summary-index.sh" "$kb"
"$SKILL_DIR/scripts/doctor-local.sh" "$kb"
"$SKILL_DIR/scripts/check-kb.sh" "$kb" --quiet

[[ -f "$kb/AI_SUMMARY_INDEX.md" ]] || fail "AI_SUMMARY_INDEX.md missing"

grep -Fq "2099-01-01" "$kb/AI_SUMMARY_INDEX.md" || fail "AI_SUMMARY_INDEX.md missing expected date"
grep -Fq "Smoke test MCP \\| timeout" "$kb/INDEX.md" || fail "INDEX.md did not escape table pipe character"

# 生成的记录骨架必须覆盖模板章节
for section in 一句话结论 原始现象 根因分析 最终解决方案 验证方法 复用经验 后续事项; do
  grep -Fq "## $section" "$record_path" || fail "record skeleton missing section: $section"
done
grep -Eq "^id: 2099-01-01-001" "$record_path" || fail "record skeleton missing id front matter"

# AI 摘要索引：生成区外的手工笔记必须保留
printf 'manual note\n' >> "$kb/AI_SUMMARY_INDEX.md"
"$SKILL_DIR/scripts/update-ai-summary-index.sh" "$kb" >/dev/null
grep -Fq "manual note" "$kb/AI_SUMMARY_INDEX.md" || fail "AI_SUMMARY_INDEX.md did not preserve manual notes"

# 7 列表头（ID/日期/标题/工具/状态/关键根因/记录）也必须能正确插入
kb7="$tmp/kb7"
mkdir -p "$kb7/records/2026"
cp "$SKILL_DIR/assets/minimal-knowledge-base/AI入口.md" "$kb7/"
cat > "$kb7/INDEX.md" <<'EOF'
# 问题索引

| ID | 日期 | 标题 | 工具/系统 | 状态 | 关键根因 | 记录 |
|---|---|---|---|---|---|---|
| 2098-01-01-001 | 2098-01-01 | older record | bash | 已解决 | 示例 | [查看](records/2026/2098-01-01-001-older.md) |

## 常用标签

- `bash`
EOF
"$SKILL_DIR/scripts/new-record.sh" "Seven column index" --root "$kb7" --date 2099-02-02 --tools bash >/dev/null
new_row_line="$(grep -n '^| 2099-02-02' "$kb7/INDEX.md" | cut -d: -f1 || true)"
tags_line="$(grep -n '^## 常用标签' "$kb7/INDEX.md" | cut -d: -f1 || true)"
[[ -n "$new_row_line" ]] || fail "7-column INDEX.md did not receive a new row"
[[ "$new_row_line" -lt "$tags_line" ]] || fail "7-column INDEX.md row was appended after the tag section"
[[ "$(awk -F'|' -v n="$new_row_line" 'NR == n { print NF - 2 }' "$kb7/INDEX.md")" -eq 7 ]] || fail "7-column INDEX.md row has wrong column count"

# 密钥扫描：真实密钥要拦住，技术文本里的 sk-/session 片段不能误报
kbscan="$tmp/kbscan"
mkdir -p "$kbscan/records/2026"
cp "$SKILL_DIR/assets/minimal-knowledge-base/AI入口.md" "$kbscan/"
printf '| [async](async-video-task-polling-and-content-url-debugging.md) |\n/cross-session:check-inbox\ncurl "http://127.0.0.1:18880/api/session?session_id=81048ae67dcd&messages=1"\n' > "$kbscan/records/2026/benign.md"
"$SKILL_DIR/scripts/check-kb.sh" "$kbscan" --quiet || fail "check-kb.sh false positive on benign technical text"
printf 'OPENAI_API_KEY=sk-proj-abcdefghijklmnopqrstuvwxyz012345\n' > "$kbscan/records/2026/leak.md"
if "$SKILL_DIR/scripts/check-kb.sh" "$kbscan" --quiet 2>/dev/null; then
  fail "check-kb.sh missed an obvious sk- key"
fi

printf '[ok] smoke test passed\n'
