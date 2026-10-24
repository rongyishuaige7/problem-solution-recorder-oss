#!/usr/bin/env bash
# Generate (or refresh) one periodic review file from the records.
#
# Shared by `psr review` and a knowledge base's `bin/qs`, so both produce the
# same document: markers, statistics, records, repeated problems, open/closed
# follow-ups, method candidates.
#
# Usage: generate-review.sh <root> <day|week|month> <key> [--dry-run]
# Exit: 0 written/no change, 1 marker conflict, 2 read failure.
set -euo pipefail

SCRIPT_DIR="$( ( unset CDPATH; cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P ) )"

die() {
  printf 'generate-review: %s\n' "$*" >&2
  exit 2
}

[[ $# -ge 3 ]] || die "用法: generate-review.sh <root> <day|week|month> <key> [--dry-run]"

root="$1"
period="$2"
key="$3"
shift 3

dry_run=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) dry_run=1; shift ;;
    *) die "未知参数: $1" ;;
  esac
done

case "$period" in
  day) label="每日" ;;
  week) label="每周" ;;
  month) label="每月" ;;
  *) die "未知周期: $period" ;;
esac

# 知识库优先用自己 bin/lib 的副本；直接跑 skill 时回落到本目录的 lib。
if [[ -f "$root/bin/lib/record-fields.awk" ]]; then
  LIB="$root/bin/lib"
else
  LIB="$SCRIPT_DIR/lib"
fi
[[ -f "$LIB/record-fields.awk" ]] || die "缺少解析器: $LIB/record-fields.awk"
[[ -f "$LIB/enumerate.sh" ]] || die "缺少枚举库: $LIB/enumerate.sh"
[[ -f "$LIB/lock.sh" ]] || die "缺少锁库: $LIB/lock.sh"

# shellcheck source=/dev/null
. "$LIB/enumerate.sh"

iso_week() {
  local d="$1"
  if date -d "$d" +%G-W%V >/dev/null 2>&1; then
    date -d "$d" +%G-W%V
    return 0
  fi
  if date -j -f "%Y-%m-%d" "$d" +%G-W%V >/dev/null 2>&1; then
    date -j -f "%Y-%m-%d" "$d" +%G-W%V
    return 0
  fi
  return 1
}

tmpd="$(mktemp -d "${TMPDIR:-/tmp}/psr-review.XXXXXX")"
REVIEW_TMPDIR="$tmpd"
trap 'rm -rf "${REVIEW_TMPDIR:-}"' EXIT

# 先拿写锁再读记录：否则“旧任务”会带着旧快照在锁外等待，
# 恢复后把新任务刚写好的复盘覆盖回去。
# --dry-run 是只读预览：不加锁，只读库（0555）也能跑。
if [[ "$dry_run" -eq 0 ]]; then
  # shellcheck source=/dev/null
  . "$LIB/lock.sh"
  REVIEW_LOCK_ROOT="$root"
  trap 'psr_lock_release "$REVIEW_LOCK_ROOT" 2>/dev/null || true; rm -rf "${REVIEW_TMPDIR:-}"' EXIT
  trap 'psr_lock_release "$REVIEW_LOCK_ROOT" 2>/dev/null || true; rm -rf "${REVIEW_TMPDIR:-}"; exit 130' INT TERM HUP
  psr_lock_acquire "$root" || die "获取写锁失败"

  if [[ -n "${PSR_REVIEW_TEST_PAUSE:-}" ]]; then
    # 仅用于回归测试放大持锁窗口；默认不生效。
    sleep "$PSR_REVIEW_TEST_PAUSE"
  fi
fi


list="$tmpd/list"
if ! psr_list_records "$root/records" "$list"; then
  printf 'generate-review: 读取记录失败，未写入复盘\n' >&2
  exit 2
fi

files=()
while IFS= read -r f; do
  files+=("$f")
done < "$list"

if [[ ${#files[@]} -eq 0 ]]; then
  : > "$tmpd/tsv"
else
  LC_ALL=C awk -v root="$root" -v maxlines=1000000 -f "$LIB/record-fields.awk" "${files[@]}" > "$tmpd/raw" 2>/dev/null || {
    printf 'generate-review: 解析记录失败，未写入复盘\n' >&2
    exit 2
  }
  LC_ALL=C awk -F'\t' '
    function emit() {
      printf "%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\n", \
        rel, v["id"], v["date"], v["title"], v["status"], v["tools"], v["tags"], \
        v["signature"], v["root"], v["fix"], v["verify"], v["reuse"], v["follow_items"], v["summary"]
    }
    $1 == "@R" { if (rel != "") emit(); rel = $2; delete v; next }
    $1 == "@F" { v[$2] = $3; next }
    END { if (rel != "") emit() }
  ' "$tmpd/raw" > "$tmpd/tsv"
fi

keep="$tmpd/keep"
: > "$keep"
while IFS=$'\037' read -r rel _id rdate _rest; do
  [[ -n "$rel" ]] || continue
  case "$period" in
    week)
      w="$(iso_week "$rdate")" || continue
      [[ "$w" == "$key" ]] || continue
      ;;
    month) [[ "${rdate:0:7}" == "$key" ]] || continue ;;
    day) [[ "$rdate" == "$key" ]] || continue ;;
  esac
  printf '%s\n' "$rel" >> "$keep"
done < "$tmpd/tsv"

block="$(LC_ALL=C awk -F'\037' \
  -v key="$key" -v label="$label" -v now="$(date '+%F %T')" \
  'NR == FNR { keep[$0] = 1; next } ($1 in keep) { print }' "$keep" "$tmpd/tsv" | LC_ALL=C awk -F'\037' \
  -v key="$key" -v label="$label" -v now="$(date '+%F %T')" '
  function addcount(map, srcmap, name, rel) {
    map[name]++
    if (index(srcmap[name], rel) == 0) srcmap[name] = srcmap[name] " " rel
  }
  {
    rel = $1; id = $2; date = $3; title = $4; status = $5
    tools = $6; tags = $7; sig = $8; root = $9; fix = $10
    verify = $11; reuse = $12; follow = $13

    nrec++
    st[status]++
    recs[nrec] = sprintf("- [%s] %s（%s）— %s", status, title, date, rel)

    nt = split(tags, tg, ", ")
    for (i = 1; i <= nt; i++) if (tg[i] != "") addcount(tagc, tagsrc, tg[i], rel)
    nl = split(tools, tl, ", ")
    for (i = 1; i <= nl; i++) if (tl[i] != "") addcount(toolc, toolsrc, tl[i], rel)

    if (reuse != "") {
      ncand++
      cand[ncand] = sprintf("- %s — %s\n  - 复用经验：%s", title, rel, reuse)
    }

    nf = split(follow, items, "\036")
    for (i = 1; i <= nf; i++) {
      it = items[i]
      if (it ~ /^\[[ xX]\] 是否需要/) next
      if (it ~ /^\[ \]/) {
        nopen++
        openitem[nopen] = sprintf("- %s — %s", it, rel)
      } else if (it ~ /^\[[xX]\]/) {
        ndone++
        doneitem[ndone] = sprintf("- %s — %s", it, rel)
      }
    }
  }
  END {
    printf "# %s复盘：%s\n\n", label, key
    printf "生成时间：%s\n\n", now
    printf "## 统计\n\n"
    printf "- 记录数：%d\n", nrec
    printf "- 状态分布："
    first = 1
    for (s in st) {
      if (!first) printf " / "
      printf "%s %d", s, st[s]
      first = 0
    }
    if (first) printf "无"
    printf "\n"
    printf "- 未完成事项：%d 项；已完成事项：%d 项\n\n", nopen, ndone

    printf "## 本期记录\n\n"
    if (nrec == 0) printf "- 本期没有记录。\n"
    else for (i = 1; i <= nrec; i++) printf "%s\n", recs[i]
    printf "\n"

    printf "## 重复问题\n\n"
    any = 0
    for (t in tagc) {
      if (tagc[t] >= 2) {
        any = 1
        printf "- 标签 %s 出现 %d 次：%s\n", t, tagc[t], tagsrc[t]
      }
    }
    for (t in toolc) {
      if (toolc[t] >= 2) {
        any = 1
        printf "- 工具 %s 出现 %d 次：%s\n", t, toolc[t], toolsrc[t]
      }
    }
    if (!any) printf "- 本期没有重复出现的标签或工具。\n"
    printf "\n"

    printf "## 未完成后续事项\n\n"
    if (nopen == 0) printf "- 无。\n"
    else for (i = 1; i <= nopen; i++) printf "%s\n", openitem[i]
    printf "\n"

    printf "## 已完成事项（不计入待办）\n\n"
    if (ndone == 0) printf "- 无。\n"
    else for (i = 1; i <= ndone; i++) printf "%s\n", doneitem[i]
    printf "\n"

    printf "## 方法候选\n\n"
    if (ncand == 0) printf "- 本期没有可沉淀的方法候选。\n"
    else for (i = 1; i <= ncand; i++) printf "%s\n", cand[i]
    printf "\n"
  }
')"

begin='<!-- PSR:BEGIN REVIEW -->'
endm='<!-- PSR:END REVIEW -->'
generated="$block"
file="$root/reviews/$key.md"

if [[ -n "${PSR_REVIEW_TEST_PAUSE_AFTER_BUILD:-}" ]]; then
  # 仅用于回归测试：模拟“旧任务已算完、尚未写入”的窗口（此时应已持锁）。
  sleep "$PSR_REVIEW_TEST_PAUSE_AFTER_BUILD"
fi

if [[ "$dry_run" -eq 1 ]]; then
  printf '%s\n\n%s\n' "$begin" "$generated"
  printf '%s\n' "$endm"
  exit 0
fi

mkdir -p "$root/reviews"

sub_begin=0 sub_end=0 begin_count=0 end_count=0 begin_line=0 end_line=0
if [[ -f "$file" ]]; then
  sub_begin="$(grep -c -F "$begin" "$file" || true)"
  sub_end="$(grep -c -F "$endm" "$file" || true)"
  begin_count="$(grep -c -x -F "$begin" "$file" || true)"
  end_count="$(grep -c -x -F "$endm" "$file" || true)"
  begin_line="$(grep -n -x -F "$begin" "$file" | head -n 1 | cut -d: -f1 || true)"
  end_line="$(grep -n -x -F "$endm" "$file" | head -n 1 | cut -d: -f1 || true)"
fi

tmp="$(mktemp "${TMPDIR:-/tmp}/psr-review.XXXXXX")"
backup=""

if [[ ! -f "$file" || ! -s "$file" ]]; then
  {
    printf '%s\n\n%s\n' "$begin" "$generated"
    printf '%s\n\n' "$endm"
    printf '## 手工笔记\n\n'
    printf '本区在重新生成复盘时保留，可自由编辑。\n'
  } > "$tmp"
elif [[ "$begin_count" -eq 1 && "$end_count" -eq 1 && -n "$begin_line" && -n "$end_line" && "$begin_line" -lt "$end_line" ]]; then
  current="$(awk -v b="$begin" -v e="$endm" '$0 == b { f = 1 } f { print } $0 == e { f = 0 }' "$file" | LC_ALL=C awk '/^生成时间：/ { print "生成时间：X"; next } { print }')"
  newblock="$( { printf '%s\n\n%s\n' "$begin" "$generated"; printf '%s\n' "$endm"; } | LC_ALL=C awk '/^生成时间：/ { print "生成时间：X"; next } { print }')"
  if [[ "$current" == "$newblock" ]]; then
    printf '复盘无变化: %s\n' "$file"
    rm -f "$tmp"
    exit 0
  fi
  {
    awk -v b="$begin" -v e="$endm" '$0 == b { exit } { print }' "$file"
    printf '%s\n\n%s\n' "$begin" "$generated"
    printf '%s\n' "$endm"
    awk -v b="$begin" -v e="$endm" 'f { print } $0 == e { f = 1 }' "$file"
  } > "$tmp"
elif [[ "$sub_begin" -eq 0 && "$sub_end" -eq 0 ]]; then
  # 纯手写的历史复盘：先备份，再把旧内容整段保留，绝不直接覆盖。
  backup="${file}.pre-marker.$(date +%Y%m%d%H%M%S).bak"
  cp -p "$file" "$backup"
  {
    printf '%s\n\n%s\n' "$begin" "$generated"
    printf '%s\n\n' "$endm"
    printf '## 历史内容（迁移自旧文件）\n\n'
    printf '以下内容来自没有生成标记的旧文件，已原样保留。\n\n'
    cat "$backup"
  } > "$tmp"
else
  printf '[fail] %s 的生成标记异常，未写入。\n' "$file" >&2
  printf '  独占整行的 BEGIN：%s 个（行号 %s）\n' "$begin_count" "${begin_line:-无}" >&2
  printf '  独占整行的 END：%s 个（行号 %s）\n' "$end_count" "${end_line:-无}" >&2
  printf '要求各一个、独占整行，且 BEGIN 严格早于 END；原文件未改动。\n' >&2
  printf '如需迁移旧文件，请先删掉所有 marker 行再重试（会备份原文件）。\n' >&2
  rm -f "$tmp"
  exit 1
fi

mv "$tmp" "$file"
printf '已生成: %s\n' "$file"
if [[ -n "$backup" ]]; then
  printf '旧文件已备份: %s\n' "$backup"
fi
