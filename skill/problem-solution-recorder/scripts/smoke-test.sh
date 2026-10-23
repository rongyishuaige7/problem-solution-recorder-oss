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
PSR="$SKILL_DIR/bin/psr"

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
  # BASH_LINENO[0] 是调用 fail 的那一行，便于在 CI 日志里定位。
  printf '[fail] %s (line %s)\n' "$*" "${BASH_LINENO[0]:-?}" >&2
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

if [[ "$(id -u)" -eq 0 ]]; then
  pass "密钥扫描：root 环境跳过无读权限用例"
else
  printf 'X=sk-proj-abcdefghijklmnopqrstuvwxyz012345\n' > "$kb_scan/records/2026/perm.md"
  chmod 000 "$kb_scan/records/2026/perm.md"
  set +e
  "$CHECK" "$kb_scan" --quiet >/dev/null 2>&1
  perm_rc=$?
  set -e
  chmod 644 "$kb_scan/records/2026/perm.md"
  [[ "$perm_rc" -eq 2 ]] || fail "unreadable file exited $perm_rc (expected 2: scan failed, not clean)"
fi
pass "密钥扫描：路径/同行情景不漏报，错误码与脱敏正确"

# ---------------------------------------------------------------- P3 安装 dry-run
"$INSTALL" --dir "$tmp/install-target" --dry-run >/dev/null
[[ -e "$tmp/install-target" ]] && fail "install.sh --dry-run created the target directory"
pass "install --dry-run 不写文件系统"

# ---------------------------------------------------------------- 摘要读取失败不得覆盖索引
kb_unread="$tmp/kb-unread"
"$INIT" "$kb_unread" >/dev/null
"$NEW" "Readable" --root "$kb_unread" --date 2099-09-09 >/dev/null
"$SUMMARY" "$kb_unread" >/dev/null
cp "$kb_unread/AI_SUMMARY_INDEX.md" "$tmp/summary-before"
if [[ "$(id -u)" -eq 0 ]]; then
  # root 会绕过权限位，无法用 chmod 000 模拟读取失败（CI 与本地都是非 root）。
  pass "不可读记录：root 环境跳过权限用例"
else
  printf 'X=1\n' > "$kb_unread/records/2099/2099-09-10-001-locked.md"
  chmod 000 "$kb_unread/records/2099/2099-09-10-001-locked.md"
  set +e
  "$SUMMARY" "$kb_unread" >/dev/null 2>&1
  unread_rc=$?
  set -e
  chmod 644 "$kb_unread/records/2099/2099-09-10-001-locked.md"
  [[ "$unread_rc" -ne 0 ]] || fail "summary index reported success with an unreadable record"
  cmp -s "$tmp/summary-before" "$kb_unread/AI_SUMMARY_INDEX.md" || fail "summary index was overwritten despite a read failure"
  pass "不可读记录时摘要索引报错且不覆盖"
fi

# ---------------------------------------------------------------- 信号终止写入
kb_sig="$tmp/kb-signal"
"$INIT" "$kb_sig" >/dev/null
mkdir "$kb_sig/.psr.lock"
printf '999999\n' > "$kb_sig/.psr.lock/pid"
mkdir "$tmp/fakebin"
cat > "$tmp/fakebin/sleep" <<'FAKE_SLEEP'
#!/usr/bin/env bash
kill -TERM "$PPID" 2>/dev/null
exit 0
FAKE_SLEEP
chmod +x "$tmp/fakebin/sleep"
set +e
PATH="$tmp/fakebin:$PATH" "$NEW" "Signal test" --root "$kb_sig" --date 2099-10-10 >/dev/null 2>&1
sig_rc=$?
set -e
[[ "$sig_rc" -eq 130 ]] || fail "SIGTERM during lock wait exited $sig_rc (expected 130)"
[[ -z "$(find "$kb_sig/records" -name '2099-10-10-*' 2>/dev/null)" ]] || fail "record was created after SIGTERM"
[[ -d "$kb_sig/.psr.lock" ]] || fail "signal handler removed another process's lock"
pass "SIGTERM 终止写入并保留他人锁"

# ---------------------------------------------------------------- 共享锁：重建索引遵守同一把锁
kb_shared="$tmp/kb-shared"
"$INIT" "$kb_shared" >/dev/null
"$NEW" "Shared lock" --root "$kb_shared" --date 2099-11-11 >/dev/null
mkdir "$kb_shared/.psr.lock"
printf '999999\n' > "$kb_shared/.psr.lock/pid"
set +e
PSR_LOCK_RETRIES=1 "$REBUILD" "$kb_shared" --check >/dev/null 2>&1
shared_rc=$?
set -e
rm -rf "$kb_shared/.psr.lock"
[[ "$shared_rc" -ne 0 ]] || fail "rebuild-index.sh ignored the knowledge base write lock"

mkdir "$kb_shared/.psr.lock"
printf '999999\n' > "$kb_shared/.psr.lock/pid"
set +e
PSR_LOCK_RETRIES=1 "$SUMMARY" "$kb_shared" >/dev/null 2>&1
summary_rc=$?
set -e
rm -rf "$kb_shared/.psr.lock"
[[ "$summary_rc" -ne 0 ]] || fail "update-ai-summary-index.sh ignored the knowledge base write lock"
pass "重建与摘要都使用同一把 .psr.lock"

# ---------------------------------------------------------------- doctor：编号、空库、转义竖线
kb_doc2="$tmp/kb-doctor2"
"$INIT" "$kb_doc2" >/dev/null
mkdir -p "$kb_doc2/records/2099"
: > "$kb_doc2/records/2099/2099-01-01-1000-a.md"
: > "$kb_doc2/records/2099/2099-01-01-1001-b.md"
"$DOCTOR" "$kb_doc2" 2>&1 | grep -Fq "duplicate record IDs" && fail "doctor reported 1000/1001 as duplicate IDs"

kb_empty="$tmp/kb-empty"
"$INIT" "$kb_empty" >/dev/null
rm -rf "$kb_empty/records"
mkdir -p "$kb_empty/records"
printf '# Index\n\n| Date | Title | Status | Tools | Tags | Record |\n| --- | --- | --- | --- | --- | --- |\n| 2026-01-01 | gone | solved | - | - | [x](records/2026/gone.md) |\n' > "$kb_empty/INDEX.md"
if "$DOCTOR" "$kb_empty" >/dev/null 2>&1; then
  fail "doctor missed a broken INDEX.md link when records/ was empty"
fi

kb_pipe="$tmp/kb-pipe"
"$INIT" "$kb_pipe" >/dev/null
"$NEW" "Pipe | title" --root "$kb_pipe" --date 2099-12-12 >/dev/null
sed -i.bak 's/^status: draft/status: solved/' "$kb_pipe"/records/2099/2099-12-12-001-pipe-title.md
rm -f "$kb_pipe"/records/2099/*.bak
doctor_pipe_out="$("$DOCTOR" "$kb_pipe" 2>&1 || true)"
if ! printf '%s' "$doctor_pipe_out" | grep -Fq "status differs"; then
  printf '%s\n' "$doctor_pipe_out" >&2
  printf 'INDEX row: %s\n' "$(grep '2099-12-12' "$kb_pipe/INDEX.md" || true)" >&2
  printf 'Record status: %s\n' "$(grep -m1 '^status:' "$kb_pipe"/records/2099/*.md || true)" >&2
  fail "doctor missed status drift on a title containing an escaped pipe"
fi
pass "doctor 处理 1000/1001、空库断链与转义竖线"

# ---------------------------------------------------------------- 四位序号与空知识库
kb_seq4="$tmp/kb-seq4"
"$INIT" "$kb_seq4" >/dev/null
mkdir -p "$kb_seq4/records/2099"
: > "$kb_seq4/records/2099/2099-01-01-1000-a.md"
: > "$kb_seq4/records/2099/2099-01-01-1001-b.md"
seq4_path="$("$NEW" "Four digit" --root "$kb_seq4" --date 2099-01-01)"
case "$seq4_path" in
  *2099-01-01-1002-*) ;;
  *) fail "four-digit sequence did not continue: $seq4_path" ;;
esac
pass "四位序号继续递增（1000/1001 → 1002）"

kb_empty_new="$tmp/kb-empty-new"
"$INIT" "$kb_empty_new" >/dev/null
rm -rf "$kb_empty_new/records"
mkdir -p "$kb_empty_new/records"
rm -f "$kb_empty_new/INDEX.md"
"$SUMMARY" "$kb_empty_new" >/dev/null || fail "summary failed on an empty knowledge base"
[[ -f "$kb_empty_new/INDEX.md" ]] && fail "empty knowledge base should not have INDEX.md yet"
"$NEW" "First record" --root "$kb_empty_new" --date 2099-04-04 >/dev/null || fail "first record failed in an empty knowledge base"
[[ -f "$kb_empty_new/INDEX.md" ]] || fail "INDEX.md was not created for the first record"
grep -Fq "first-record" "$kb_empty_new/INDEX.md" || fail "first record missing from INDEX.md"
pass "空知识库：首条记录自动建索引"

# ---------------------------------------------------------------- 7 列手写列保留
kb_keep="$tmp/kb-keep"
"$INIT" "$kb_keep" >/dev/null
mkdir -p "$kb_keep/records/2098"
cat > "$kb_keep/INDEX.md" <<'EOF'
# 问题索引

| ID | 日期 | 标题 | 工具/系统 | 状态 | 关键根因 | 记录 |
|---|---|---|---|---|---|---|
| 2098-01-01-001 | 2098-01-01 | handwritten | bash | 已解决 | 人工写的根因 | [查看](records/2098/2098-01-01-001-handwritten.md) |
EOF
printf -- '---\ntitle: "handwritten"\ndate: 2098-01-01\nstatus: solved\nsummary: "生成的摘要"\n---\n\n# handwritten\n\n## 一句话结论\n\n生成的摘要\n' > "$kb_keep/records/2098/2098-01-01-001-handwritten.md"
"$REBUILD" "$kb_keep" >/dev/null
grep -Fq "人工写的根因" "$kb_keep/INDEX.md" || fail "rebuild overwrote a hand-written root cause"
"$REBUILD" "$kb_keep" --overwrite-handwritten >/dev/null
grep -Fq "生成的摘要" "$kb_keep/INDEX.md" || fail "--overwrite-handwritten did not regenerate the cell"
pass "重建保留手写列，显式覆盖才改写"

# ---------------------------------------------------------------- YAML 诊断与无变化不写
kb_yaml="$tmp/kb-yaml"
"$INIT" "$kb_yaml" >/dev/null
mkdir -p "$kb_yaml/records/2026"
printf '%s\n' '---' 'title: "YAML 诊断"' 'date: 2026-06-06' 'status: solved' 'summary: |' '  块标量' 'tools:' '  codex: 1' '---' '' '# YAML 诊断' '' '## 一句话结论' '' '结论。' > "$kb_yaml/records/2026/2026-06-06-001-yaml.md"
yaml_err="$tmp/yaml.err"
"$SUMMARY" "$kb_yaml" >/dev/null 2>"$yaml_err"
grep -Fq "unsupported YAML" "$yaml_err" || fail "unsupported YAML was not reported"
cp "$kb_yaml/AI_SUMMARY_INDEX.md" "$tmp/yaml-before"
"$SUMMARY" "$kb_yaml" >/dev/null 2>&1
cmp -s "$tmp/yaml-before" "$kb_yaml/AI_SUMMARY_INDEX.md" || fail "unchanged records still rewrote the summary index"
pass "YAML 字段级诊断；无变化时文件逐字节一致"

# ---------------------------------------------------------------- psr 完整路径
# 空库初始化 → 子目录创建快记 → 补全 → finalize → 双索引 → 幂等
kb_acc="$tmp/kb-accept"
# 本段验证“从子目录靠项目标记找到知识库”，必须让环境变量让位。
unset PROBLEM_SOLUTION_KB_ROOT
"$PSR" init "$kb_acc" >/dev/null
[[ -f "$kb_acc/INDEX.md" ]] || fail "psr init did not create INDEX.md"
[[ -z "$(find "$kb_acc/records" -type f -name '*.md' 2>/dev/null)" ]] || fail "psr init should create an empty knowledge base by default"

mkdir -p "$tmp/proj/sub"
"$PSR" configure --project "$kb_acc" --dir "$tmp/proj" >/dev/null
[[ -f "$tmp/proj/.problem-solution-root" ]] || fail "psr configure --project did not write the marker"

quick_path="$(cd "$tmp/proj/sub" && "$PSR" new "Acceptance path" --mode quick --slug acceptance | awk '/^已创建:/ { print $2 }')"
[[ -n "$quick_path" ]] || fail "psr new --mode quick failed from a subdirectory"
quick_file="$kb_acc/$quick_path"
quick_id="$(basename "$quick_file" | cut -c1-14)"

fill_record() {
  local file="$1"
  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/psr-fill.XXXXXX")"
  LC_ALL=C awk '
    /^## / { target = $0; print; next }
    target == "## 根因分析" && $0 == "-" { print "payload 过大，高延迟链路超过默认超时。"; next }
    target == "## 最终解决方案" && $0 == "-" { print "调大超时并拆分查询。"; next }
    target == "## 验证方法" && $0 == "-" { print "20 次等价查询失败率为 0。"; next }
    target == "## 限制与风险" && $0 == "-" { print "仅适用于读请求。"; next }
    { print }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

# 未补全时 finalize 必须失败，并提示记录已保存
if ( cd "$tmp/proj/sub" && "$PSR" finalize "$quick_id" --status solved ) >/dev/null 2>"$tmp/acc.err"; then
  fail "finalize accepted an empty quick record"
fi
grep -Fq "记录已保存" "$tmp/acc.err" || fail "finalize failure did not report the saved record"
grep -Fq "psr finalize $quick_id" "$tmp/acc.err" || fail "finalize failure did not print a recovery command"

fill_record "$quick_file"
( cd "$tmp/proj/sub" && "$PSR" finalize "$quick_id" --status solved ) >/dev/null
grep -Fq "status: solved" "$quick_file" || fail "finalize did not update the record status"
grep -Eq "^\| [0-9]{4}-[0-9]{2}-[0-9]{2} \| .* \| solved \|" "$kb_acc/INDEX.md" || fail "finalize did not update the INDEX status"
grep -Fq -- "- status: solved" "$kb_acc/AI_SUMMARY_INDEX.md" || fail "finalize did not update the summary index"

cp "$kb_acc/INDEX.md" "$tmp/acc-index"
cp "$kb_acc/AI_SUMMARY_INDEX.md" "$tmp/acc-summary"
( cd "$tmp/proj/sub" && "$PSR" finalize "$quick_id" --status solved ) >/dev/null
cmp -s "$tmp/acc-index" "$kb_acc/INDEX.md" || fail "second finalize changed INDEX.md"
cmp -s "$tmp/acc-summary" "$kb_acc/AI_SUMMARY_INDEX.md" || fail "second finalize changed the summary index"
pass "psr 完整路径：空库 → 子目录快记 → finalize → 双索引 → 幂等"

# 恢复全局环境变量，供后续用例使用
export PROBLEM_SOLUTION_KB_ROOT="$kb"

# ---------------------------------------------------------------- 检索与复盘
kb_sr="$tmp/kb-search"
"$PSR" init "$kb_sr" >/dev/null
mkdir -p "$kb_sr/records/2026"
cat > "$kb_sr/records/2026/2026-10-21-001-alpha.md" <<'EOF'
---
id: 2026-10-21-001
title: "Alpha timeout"
date: 2026-10-21
status: solved
tools: [codex]
tags: [mcp]
---

# Alpha timeout

## 一句话结论

Alpha 的结论。

## 原始现象

请求超时。

## 根因分析

连接池过小。

## 最终解决方案

调大连接池。

## 验证方法

20 次请求 0 失败。

## 后续事项

- [ ] 观察一周
- [x] 更新文档
EOF
cat > "$kb_sr/records/2026/2026-10-21-002-beta.md" <<'EOF'
---
id: 2026-10-21-002
title: "Beta timeout"
date: 2026-10-21
status: draft
tools: [curl]
tags: [mcp]
---

# Beta timeout

## 一句话结论

-

## 原始现象

还没定位。
EOF

export PROBLEM_SOLUTION_KB_ROOT="$kb_sr"
search_all="$("$PSR" search timeout --limit 5)"
printf '%s' "$search_all" | grep -Fq "Alpha timeout" || fail "search missed a matching title"
printf '%s' "$search_all" | grep -Fq "[draft]" || fail "search did not mark drafts"
printf '%s' "$search_all" | grep -Fq "草稿（未验证" || fail "search did not warn about drafts"

search_solved="$("$PSR" search timeout --status solved --limit 5)"
printf '%s' "$search_solved" | grep -Fq "Alpha timeout" || fail "status filter dropped the solved record"
printf '%s' "$search_solved" | grep -Fq "Beta timeout" && fail "status filter kept a draft"

[[ "$("$PSR" search timeout --limit 1 | grep -c '^1\.')" -eq 1 ]] || fail "--limit did not cap results"

"$PSR" search 'time[o]ut' --regex --limit 1 >/dev/null || fail "regex search failed"
set +e
"$PSR" search '[' --regex >/dev/null 2>&1
bad_re_rc=$?
"$PSR" search zzz-not-found >/dev/null 2>&1
no_hit_rc=$?
set -e
[[ "$bad_re_rc" -eq 2 ]] || fail "invalid regex exited $bad_re_rc (expected 2)"
[[ "$no_hit_rc" -eq 1 ]] || fail "no results exited $no_hit_rc (expected 1)"
pass "检索：多词 AND、状态筛选、草稿标识、正则与错误码"

review_file="$kb_sr/reviews/2026-10-21.md"
"$PSR" review --day 2026-10-21 >/dev/null
[[ -f "$review_file" ]] || fail "review did not create the period file"
grep -Fq "Alpha timeout" "$review_file" || fail "review missed a record in the period"
grep -Fq -- "- [ ] 观察一周" "$review_file" || fail "review lost open follow-ups"
grep -Fq -- "- [x] 更新文档" "$review_file" || fail "review lost completed follow-ups"
grep -Fq "已完成事项" "$review_file" || fail "review did not separate completed items"
cp "$review_file" "$tmp/review-before"
"$PSR" review --day 2026-10-21 >/dev/null
cmp -s "$tmp/review-before" "$review_file" || fail "second review run changed the file"
printf '\n手写复盘备注\n' >> "$review_file"
"$PSR" review --day 2026-10-21 >/dev/null
grep -Fq "手写复盘备注" "$review_file" || fail "review overwrote hand-written notes"
open_out="$("$PSR" review --open)"
printf '%s' "$open_out" | grep -Fq "观察一周" || fail "review --open missed an open item"
printf '%s' "$open_out" | grep -Fq "更新文档" && fail "review --open listed a completed item"
pass "复盘：周期记录、未完成/已完成分离、来源、幂等与手写保留"

unset PROBLEM_SOLUTION_KB_ROOT


# ---------------------------------------------------------------- 可靠性回归（v0.8.1）
# 1) 陈旧锁回收必须互斥
kb_lock="$tmp/kb-lock"
mkdir -p "$kb_lock"
mkdir "$kb_lock/.psr.lock"
printf '999999\n' > "$kb_lock/.psr.lock/pid"
touch -t 200001010000 "$kb_lock/.psr.lock"
cat > "$tmp/lock-holder.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
. "$1/scripts/lib/lock.sh"
psr_lock_acquire "$2" 100 || exit 9
sleep 1.2
psr_lock_release "$2"
EOF
cat > "$tmp/lock-contender.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
. "$1/scripts/lib/lock.sh"
if psr_lock_acquire "$2" 2; then
  psr_lock_release "$2"
  exit 0
fi
exit 1
EOF
chmod +x "$tmp/lock-holder.sh" "$tmp/lock-contender.sh"
PSR_LOCK_TEST_PAUSE=2.0 "$tmp/lock-holder.sh" "$SKILL_DIR" "$kb_lock" & lock_holder_pid=$!
# 等到回收者真正进入回收窗口再让竞争者尝试，避免用固定 sleep 赌调度。
for _ in $(seq 1 500); do
  [[ -d "$kb_lock/.psr.lock.reclaim" ]] && break
  sleep 0.02
done
[[ -d "$kb_lock/.psr.lock.reclaim" ]] || fail "holder never took the reclaim marker"
if "$tmp/lock-contender.sh" "$SKILL_DIR" "$kb_lock"; then
  fail "contender entered while a stale lock was being reclaimed"
fi
wait "$lock_holder_pid"
pass "陈旧锁回收互斥，回收窗口内其他写入者被阻塞"

# 2) 不可读记录目录不得改写摘要
if [[ "$(id -u)" -ne 0 ]]; then
  kb_enum="$tmp/kb-enum"
  "$PSR" init "$kb_enum" >/dev/null
  mkdir -p "$kb_enum/records/2026"
  printf -- '---\nid: 2026-10-21-001\ntitle: "枚举"\ndate: 2026-10-21\nstatus: solved\n---\n\n# 枚举\n\n## 根因分析\n\n真实根因。\n' > "$kb_enum/records/2026/2026-10-21-001-enum.md"
  PROBLEM_SOLUTION_KB_ROOT="$kb_enum" "$PSR" index >/dev/null
  cp "$kb_enum/AI_SUMMARY_INDEX.md" "$tmp/enum-before"
  chmod 000 "$kb_enum/records/2026"
  set +e
  "$SCRIPT_DIR/update-ai-summary-index.sh" "$kb_enum" >/dev/null 2>&1
  enum_rc=$?
  set -e
  chmod 755 "$kb_enum/records/2026"
  [[ "$enum_rc" -ne 0 ]] || fail "summary succeeded with an unreadable records directory"
  cmp -s "$tmp/enum-before" "$kb_enum/AI_SUMMARY_INDEX.md" || fail "summary changed after an enumeration failure"
  pass "目录枚举失败时摘要保持原样并返回非零"
else
  pass "目录枚举失败用例在 root 下跳过"
fi

# 3) 复盘：手写文件备份迁移、异常 marker 拒绝、遵守写锁
kb_rev="$tmp/kb-review"
"$PSR" init "$kb_rev" >/dev/null
mkdir -p "$kb_rev/records/2026" "$kb_rev/reviews"
printf -- '---\nid: 2026-10-21-001\ntitle: "复盘"\ndate: 2026-10-21\nstatus: solved\n---\n\n# 复盘\n\n## 后续事项\n\n- [ ] 跟进\n' > "$kb_rev/records/2026/2026-10-21-001-rev.md"
printf '# 手写复盘\n\n哨兵 HAND-1\n' > "$kb_rev/reviews/2026-10-21.md"
PROBLEM_SOLUTION_KB_ROOT="$kb_rev" "$PSR" review --day 2026-10-21 >/dev/null
grep -Fq "HAND-1" "$kb_rev/reviews/2026-10-21.md" || fail "review dropped hand-written history"
ls "$kb_rev/reviews/"*pre-marker*.bak >/dev/null 2>&1 || fail "review did not back up the pre-marker file"

printf '<!-- PSR:END REVIEW -->\nX\n<!-- PSR:BEGIN REVIEW -->\n' > "$kb_rev/reviews/2026-10-21.md"
cp "$kb_rev/reviews/2026-10-21.md" "$tmp/review-before"
set +e
PROBLEM_SOLUTION_KB_ROOT="$kb_rev" "$PSR" review --day 2026-10-21 >/dev/null 2>&1
rev_rc=$?
set -e
[[ "$rev_rc" -ne 0 ]] || fail "review wrote into a file with reversed markers"
cmp -s "$tmp/review-before" "$kb_rev/reviews/2026-10-21.md" || fail "review modified a file with reversed markers"

mkdir -p "$kb_rev/.psr.lock"
printf '%s\n' "$$" > "$kb_rev/.psr.lock/pid"
set +e
PROBLEM_SOLUTION_KB_ROOT="$kb_rev" PSR_LOCK_RETRIES=2 "$PSR" review --day 2026-10-21 >/dev/null 2>&1
rev_lock_rc=$?
set -e
rm -rf "$kb_rev/.psr.lock"
[[ "$rev_lock_rc" -ne 0 ]] || fail "review ignored an active write lock"
pass "复盘：手写内容迁移备份、异常 marker 拒绝、遵守写锁"

# 4) 未填写的完整模板不能归档
kb_tpl_full="$tmp/kb-template-full"
"$PSR" init "$kb_tpl_full" >/dev/null
PROBLEM_SOLUTION_KB_ROOT="$kb_tpl_full" "$PSR" new "完整模板" --slug tpl >/dev/null
tpl_id="$(basename "$(ls "$kb_tpl_full"/records/2026/*.md)" | sed -n -E 's/^([0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{3,})-.*/\1/p')"
set +e
PROBLEM_SOLUTION_KB_ROOT="$kb_tpl_full" "$PSR" finalize "$tpl_id" --status solved >/dev/null 2>"$tmp/tpl.err"
tpl_rc=$?
set -e
[[ "$tpl_rc" -ne 0 ]] || fail "unedited full template was archived as solved"
grep -Fq "模板原文" "$tmp/tpl.err" || fail "template rejection did not explain the reason"
pass "完整模板未编辑时拒绝归档"

# 5) 四位 ID、前缀拒绝、重复 ID
kb_id="$tmp/kb-ids"
"$PSR" init "$kb_id" >/dev/null
mkdir -p "$kb_id/records/2026"
printf -- '---\nid: 2026-10-21-1000\ntitle: "已存在"\ndate: 2026-10-21\nstatus: solved\n---\n\n# 已存在\n\n## 根因分析\n\n真实根因。\n' > "$kb_id/records/2026/2026-10-21-1000-old.md"
id_out="$(PROBLEM_SOLUTION_KB_ROOT="$kb_id" "$PSR" new "四位序号" --date 2026-10-21 --slug four)"
printf '%s' "$id_out" | grep -Fq "ID: 2026-10-21-1001" || fail "four-digit id was truncated in feedback"
set +e
PROBLEM_SOLUTION_KB_ROOT="$kb_id" "$PSR" finalize 2026 --status solved >/dev/null 2>&1
prefix_rc=$?
set -e
[[ "$prefix_rc" -eq 2 ]] || fail "finalize accepted a year prefix (rc=$prefix_rc)"
cp "$kb_id/records/2026/2026-10-21-1000-old.md" "$kb_id/records/2026/2026-10-21-1000-dup.md"
set +e
PROBLEM_SOLUTION_KB_ROOT="$kb_id" "$PSR" finalize 2026-10-21-1000 --status solved >/dev/null 2>&1
dup_rc=$?
set -e
[[ "$dup_rc" -eq 1 ]] || fail "finalize did not refuse duplicate ids (rc=$dup_rc)"
pass "ID 全程完整、前缀拒绝、重复 ID 拒绝"

# 6) 六列索引保留标签；敏感检查失败返回非零
kb_idx="$tmp/kb-index-tags"
"$PSR" init "$kb_idx" >/dev/null
mkdir -p "$kb_idx/records/2026"
printf -- '---\nid: 2026-10-21-001\ntitle: "标签"\ndate: 2026-10-21\nstatus: draft\ntools: [codex]\ntags: [mcp, debug]\n---\n\n# 标签\n\n## 根因分析\n\n真实根因。\n\n## 最终解决方案\n\n真实方案。\n\n## 验证方法\n\n20 次通过。\n' > "$kb_idx/records/2026/2026-10-21-001-tags.md"
cat > "$kb_idx/INDEX.md" <<'EOF'
# 问题索引

| Date | Title | Status | Tools | Tags | Record |
| --- | --- | --- | --- | --- | --- |
| 2026-10-21 | 标签 | draft | codex | mcp, debug | [records/2026/2026-10-21-001-tags.md](records/2026/2026-10-21-001-tags.md) |
EOF
PROBLEM_SOLUTION_KB_ROOT="$kb_idx" "$PSR" finalize 2026-10-21-001 --status solved >/dev/null
grep -Fq "| mcp, debug |" "$kb_idx/INDEX.md" || fail "finalize replaced six-column tags with a placeholder"

printf -- '---\nid: 2026-10-21-002\ntitle: "密钥"\ndate: 2026-10-21\nstatus: solved\n---\n\n# 密钥\n\n## 根因分析\n\n真实根因。\n\n## 最终解决方案\n\nsk-proj-abcdefghijklmnopqrstuvwx1234\n\n## 验证方法\n\n通过。\n' > "$kb_idx/records/2026/2026-10-21-002-secret.md"
set +e
PROBLEM_SOLUTION_KB_ROOT="$kb_idx" "$PSR" finalize 2026-10-21-002 --status solved >/dev/null 2>"$tmp/secret.err"
secret_rc=$?
set -e
[[ "$secret_rc" -ne 0 ]] || fail "finalize returned success although the secret check failed"
grep -Fq "敏感检查" "$tmp/secret.err" || fail "secret failure did not print a recovery hint"
pass "六列标签保留；敏感检查失败时归档门禁返回非零"

# 7) 摘要维护失败时仍报告已保存的记录
kb_part="$tmp/kb-partial"
"$PSR" init "$kb_part" >/dev/null
printf '<!-- PSR:BEGIN GENERATED -->\nonly begin\n' > "$kb_part/AI_SUMMARY_INDEX.md"
set +e
PROBLEM_SOLUTION_KB_ROOT="$kb_part" "$PSR" new "部分失败" --slug partial >/dev/null 2>"$tmp/partial.err"
part_rc=$?
set -e
[[ "$part_rc" -eq 3 ]] || fail "partial new returned $part_rc (expected 3)"
grep -Fq "记录已保存" "$tmp/partial.err" || fail "partial new did not report the saved record"
grep -Fq "（ID " "$tmp/partial.err" || fail "partial new did not include the record id"
pass "新建部分失败时给出保存位置与恢复命令"

printf '[ok] smoke test passed\n'
