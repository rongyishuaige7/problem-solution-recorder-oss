#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$( ( unset CDPATH; cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P ) )"
SKILL_DIR="$( ( unset CDPATH; cd -P -- "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd -P ) )"

NEW="$SCRIPT_DIR/new-record.sh"
INIT="$SCRIPT_DIR/init-kb.sh"
SUMMARY="$SCRIPT_DIR/update-ai-summary-index.sh"
DOCTOR="$SCRIPT_DIR/doctor-local.sh"
CHECK="$SCRIPT_DIR/check-kb.sh"
REBUILD="$SCRIPT_DIR/rebuild-index.sh"
INSTALL="$SCRIPT_DIR/install.sh"

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
  chmod -R u+rwX "$tmp" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

fail() {
  printf '[fail] %s\n' "$*" >&2
  exit 1
}

pass() {
  printf '[ok] %s\n' "$*"
}

# ---------------------------------------------------------------- 基础流程
kb="$tmp/kb"
export PROBLEM_SOLUTION_KB_ROOT="$kb"

"$INIT" "$kb" >/dev/null
record_path="$("$NEW" "Smoke test MCP | timeout" --root "$kb" --date 2099-01-01 --tools "bash,codex" --tags "smoke,mcp")"

[[ -f "$record_path" ]] || fail "new record file missing: $record_path"

"$SUMMARY" "$kb" >/dev/null
"$DOCTOR" "$kb" >/dev/null
"$CHECK" "$kb" --quiet

[[ -f "$kb/AI_SUMMARY_INDEX.md" ]] || fail "AI_SUMMARY_INDEX.md missing"
grep -Fq "2099-01-01" "$kb/AI_SUMMARY_INDEX.md" || fail "AI_SUMMARY_INDEX.md missing expected date"
grep -Fq "Smoke test MCP \\| timeout" "$kb/INDEX.md" || fail "INDEX.md did not escape table pipe character"

for section in 一句话结论 原始现象 根因分析 最终解决方案 验证方法 复用经验 后续事项; do
  grep -Fq "## $section" "$record_path" || fail "record skeleton missing section: $section"
done
grep -Eq "^id: 2099-01-01-001" "$record_path" || fail "record skeleton missing id front matter"
pass "基础流程（初始化 → 建记录 → 索引 → doctor）"

# ---------------------------------------------------------------- 手工笔记保留
printf 'manual note\n' >> "$kb/AI_SUMMARY_INDEX.md"
"$SUMMARY" "$kb" >/dev/null
grep -Fq "manual note" "$kb/AI_SUMMARY_INDEX.md" || fail "AI_SUMMARY_INDEX.md did not preserve manual notes"
pass "摘要索引保留生成区外的手工笔记"

# ---------------------------------------------------------------- P1-1 初始化保护
kb_full="$tmp/kb-full"
mkdir -p "$kb_full"
printf 'SENTINEL\n' > "$kb_full/AI入口.md"
if "$INIT" "$kb_full" >/dev/null 2>&1; then
  fail "init-kb.sh overwrote a non-empty directory without --force"
fi
[[ "$(head -1 "$kb_full/AI入口.md")" == "SENTINEL" ]] || fail "init-kb.sh modified files despite refusing"
"$INIT" "$kb_full" --force >/dev/null || fail "init-kb.sh --force failed"
backup_file="$(find "$kb_full" -maxdepth 2 -path '*.psr-backup-*' -name 'AI入口.md' | head -1)"
[[ -n "$backup_file" && "$(head -1 "$backup_file")" == "SENTINEL" ]] || fail "init-kb.sh --force did not back up the overwritten file"
pass "非空目录保护与 --force 备份"

# ---------------------------------------------------------------- P1-2 并发与序号
kb_conc="$tmp/kb-concurrent"
"$INIT" "$kb_conc" >/dev/null
for i in 1 2 3 4; do
  ( "$NEW" "Concurrent $i" --root "$kb_conc" --date 2099-05-05 >/dev/null 2>&1 ) &
done
wait || true
conc_files="$(find "$kb_conc/records/2099" -type f -name '*.md' | wc -l | tr -d ' ')"
conc_ids="$(find "$kb_conc/records/2099" -type f -name '*.md' | sed -E 's|.*/||' | cut -c1-14 | sort -u | wc -l | tr -d ' ')"
conc_rows="$(grep -c '^| 2099-05-05' "$kb_conc/INDEX.md" | tr -d ' ')"
[[ "$conc_files" -eq 4 ]] || fail "concurrent writes produced $conc_files files (expected 4)"
[[ "$conc_ids" -eq 4 ]] || fail "concurrent writes produced $conc_ids distinct IDs (expected 4)"
[[ "$conc_rows" -eq 4 ]] || fail "concurrent writes produced $conc_rows index rows (expected 4)"
[[ -d "$kb_conc/.psr.lock" ]] && fail "write lock was left behind"
pass "并发写入：4 个进程 → 4 个唯一 ID、4 行索引、无残留锁"

kb_seq="$tmp/kb-seq"
"$INIT" "$kb_seq" >/dev/null
mkdir -p "$kb_seq/records/2099"
: > "$kb_seq/records/2099/2099-06-06-999-old.md"
: > "$kb_seq/records/2099/2099-06-06-1000-older.md"
seq_path="$("$NEW" "Sequence overflow" --root "$kb_seq" --date 2099-06-06)"
case "$seq_path" in
  *2099-06-06-1001-*) ;;
  *) fail "sequence after 1000 was wrong: $seq_path" ;;
esac
[[ -f "$kb_seq/records/2099/2099-06-06-1000-older.md" ]] || fail "sequence overflow overwrote an existing record"
pass "序号超过 999 后继续递增且不覆盖"

# ---------------------------------------------------------------- P2-7 补录旧日期
kb_order="$tmp/kb-order"
"$INIT" "$kb_order" >/dev/null
"$NEW" "Newer" --root "$kb_order" --date 2026-01-20 >/dev/null
"$NEW" "Backfilled" --root "$kb_order" --date 2025-12-01 >/dev/null
last_row="$(grep -E '^\| 20' "$kb_order/INDEX.md" | tail -1)"
case "$last_row" in
  *2025-12-01*) ;;
  *) fail "backfilled older record was not placed last: $last_row" ;;
esac
pass "补录旧日期仍保持日期倒序"

# ---------------------------------------------------------------- P2-5 自定义模板
kb_tpl="$tmp/kb-template"
"$INIT" "$kb_tpl" >/dev/null
printf '\n## 团队自定义章节\n\n- 填写人：\n' >> "$kb_tpl/_templates/问题记录模板.md"
tpl_record="$("$NEW" "Template override" --root "$kb_tpl" --date 2099-07-07)"
grep -Fq "## 团队自定义章节" "$tpl_record" || fail "new-record.sh ignored the knowledge base template"
pass "记录骨架使用知识库模板"

# ---------------------------------------------------------------- P2-4 摘要解析
kb_parse="$tmp/kb-parse"
"$INIT" "$kb_parse" >/dev/null
mkdir -p "$kb_parse/records/2026"
cat > "$kb_parse/records/2026/2026-05-01-001-parse.md" <<'EOF'
---
title: "解析测试"
date: 2026-05-01
status: solved
tools:
  - codex
  - claude-code
tags: [mcp, debug]
---

# 解析测试

## 一句话结论

结论一句话。

## 原始现象

现象第一行。

```text
## 这不是标题
围栏内的日志不应进入摘要。
```

现象第二行，必须仍然被抓到。

## 根因分析

根因内容。
EOF
"$SUMMARY" "$kb_parse" >/dev/null
grep -Fq -- "- tools: codex, claude-code" "$kb_parse/AI_SUMMARY_INDEX.md" || fail "multi-line YAML tools list not parsed"
grep -Fq -- "- tags: mcp, debug" "$kb_parse/AI_SUMMARY_INDEX.md" || fail "inline YAML tags list not parsed"
grep -Fq "现象第二行" "$kb_parse/AI_SUMMARY_INDEX.md" || fail "fenced code block truncated the section summary"
if grep -Fq "围栏内的日志" "$kb_parse/AI_SUMMARY_INDEX.md"; then
  fail "fenced code content leaked into the summary"
fi
pass "多行 YAML 列表与代码围栏解析"

# ---------------------------------------------------------------- P2-8 标记异常
kb_marker="$tmp/kb-marker"
"$INIT" "$kb_marker" >/dev/null
printf 'A\n<!-- PSR:END GENERATED -->\nMANUAL-KEEP\n<!-- PSR:BEGIN GENERATED -->\nB\n' > "$kb_marker/AI_SUMMARY_INDEX.md"
cp "$kb_marker/AI_SUMMARY_INDEX.md" "$tmp/marker-before"
if "$SUMMARY" "$kb_marker" >/dev/null 2>&1; then
  fail "update-ai-summary-index.sh accepted reversed markers"
fi
cmp -s "$tmp/marker-before" "$kb_marker/AI_SUMMARY_INDEX.md" || fail "update-ai-summary-index.sh modified a file with malformed markers"
pass "标记顺序异常时拒绝写入并保留原文件"

# ---------------------------------------------------------------- P2-6 索引重建与诊断
kb_doc="$tmp/kb-doctor"
"$INIT" "$kb_doc" >/dev/null
"$NEW" "Doctor subject" --root "$kb_doc" --date 2099-08-08 >/dev/null
"$REBUILD" "$kb_doc" --check >/dev/null || fail "rebuild-index --check reported a fresh index as stale"
rm "$kb_doc/records/2099/2099-08-08-001-doctor-subject.md"
if "$DOCTOR" "$kb_doc" >/dev/null 2>&1; then
  fail "doctor-local.sh did not notice a broken INDEX.md link"
fi
pass "索引可重建，doctor 能发现断链"

# ---------------------------------------------------------------- P1-3 密钥扫描
kb_scan="$tmp/examples/kb-scan"
mkdir -p "$kb_scan/records/2026"
cp "$SKILL_DIR/assets/minimal-knowledge-base/AI入口.md" "$kb_scan/"
printf '| [async](async-video-task-polling-and-content-url-debugging.md) |\n/cross-session:check-inbox\ncurl "http://127.0.0.1:18880/api/session?session_id=81048ae67dcd&messages=1"\n' > "$kb_scan/records/2026/benign.md"
"$CHECK" "$kb_scan" --quiet || fail "check-kb.sh false positive on benign technical text"

printf 'OPENAI_API_KEY=sk-proj-abcdefghijklmnopqrstuvwxyz012345\n' > "$kb_scan/records/2026/leak.md"
if "$CHECK" "$kb_scan" --quiet >/dev/null 2>&1; then
  fail "check-kb.sh missed a key under a path containing 'examples'"
fi

printf '示例 [REDACTED] 但真实值 sk-proj-abcdefghijklmnopqrstuvwxyz012345\n' > "$kb_scan/records/2026/leak.md"
if "$CHECK" "$kb_scan" --quiet >/dev/null 2>&1; then
  fail "check-kb.sh let [REDACTED] suppress a real secret on the same line"
fi
check_err="$tmp/check.err"
"$CHECK" "$kb_scan" --quiet >/dev/null 2>"$check_err" || true
if grep -Fq "sk-proj-abcdefghijklmnopqrstuvwxyz012345" "$check_err"; then
  fail "check-kb.sh printed the full secret value"
fi
grep -Fq "sk-p…2345" "$check_err" || fail "check-kb.sh did not mask the reported secret"
rm -f "$kb_scan/records/2026/leak.md"

printf 'foo([\n' > "$tmp/bad-allow.txt"
set +e
"$CHECK" "$kb_scan" --allow "$tmp/bad-allow.txt" --quiet >/dev/null 2>&1
allow_rc=$?
set -e
[[ "$allow_rc" -eq 2 ]] || fail "invalid allowlist pattern exited $allow_rc (expected 2)"

printf 'X=sk-proj-abcdefghijklmnopqrstuvwxyz012345\n' > "$kb_scan/records/2026/perm.md"
chmod 000 "$kb_scan/records/2026/perm.md"
set +e
"$CHECK" "$kb_scan" --quiet >/dev/null 2>&1
perm_rc=$?
set -e
chmod 644 "$kb_scan/records/2026/perm.md"
[[ "$perm_rc" -eq 2 ]] || fail "unreadable file exited $perm_rc (expected 2: scan failed, not clean)"
pass "密钥扫描：路径/同行情景不漏报，错误码与脱敏正确"

# ---------------------------------------------------------------- P3 安装 dry-run
"$INSTALL" --dir "$tmp/install-target" --dry-run >/dev/null
[[ -e "$tmp/install-target" ]] && fail "install.sh --dry-run created the target directory"
pass "install --dry-run 不写文件系统"

printf '[ok] smoke test passed\n'
