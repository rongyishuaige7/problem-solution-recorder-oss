#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$( ( unset CDPATH; cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P ) )"
RESOLVE="$SCRIPT_DIR/resolve-kb-root.sh"

root="$("$RESOLVE" "${1:-}")"
records_dir="$root/records"
target="$root/AI_SUMMARY_INDEX.md"

begin_marker='<!-- PSR:BEGIN GENERATED -->'
end_marker='<!-- PSR:END GENERATED -->'

gen_main="$(mktemp "${TMPDIR:-/tmp}/psr-summary-main.XXXXXX")"
gen_draft="$(mktemp "${TMPDIR:-/tmp}/psr-summary-draft.XXXXXX")"
generated="$(mktemp "${TMPDIR:-/tmp}/psr-summary-generated.XXXXXX")"
merged="$(mktemp "${TMPDIR:-/tmp}/psr-summary-merged.XXXXXX")"
backup=""

cleanup() {
  rm -f "$gen_main" "$gen_draft" "$generated" "$merged"
}
trap cleanup EXIT

: > "$gen_main"
: > "$gen_draft"

records_main=0
records_draft=0
cur_rel=""

CAP=""
cap_text() {
  CAP="$1"
  if [[ ${#CAP} -gt 300 ]]; then
    CAP="${CAP:0:297}…"
  fi
}

reset_record_vars() {
  id=""
  title_value=""
  date_value=""
  status_value=""
  tools_value=""
  tags_value=""
  summary=""
  fm_summary=""
  signature=""
  root_cause=""
  final_fix=""
  verification=""
  reusable_lesson=""
  follow_up=""
}

reset_record_vars

emit_record() {
  [[ -n "$cur_rel" ]] || return 0

  base_name="${cur_rel##*/}"
  base_name="${base_name%.md}"
  if [[ -z "$id" ]]; then
    if [[ "$base_name" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{3} ]]; then
      id="${BASH_REMATCH[0]}"
    else
      id="${date_value}-${base_name}"
    fi
  fi
  [[ -n "$date_value" ]] || date_value="${base_name:0:10}"
  [[ -n "$status_value" ]] || status_value="unknown"
  [[ -n "$tools_value" ]] || tools_value="-"
  [[ -n "$tags_value" ]] || tags_value="-"
  [[ -n "$title_value" ]] || title_value="$cur_rel"

  # problem_signature 取值顺序：front matter summary > 原始现象 > 一句话结论
  problem_signature="$fm_summary"
  [[ -n "$problem_signature" ]] || problem_signature="$signature"
  [[ -n "$problem_signature" ]] || problem_signature="$summary"
  [[ -n "$problem_signature" ]] || problem_signature="-"

  # 草稿（未填写）不进入主召回区，避免把空记录当成结论。
  is_draft=0
  case "$status_value" in
    draft|inbox) is_draft=1 ;;
  esac
  if [[ "$is_draft" -eq 0 && "$problem_signature" == "-" ]]; then
    is_draft=1
  fi

  if [[ "$is_draft" -eq 1 ]]; then
    printf -- '- `%s` — %s (status: %s)\n' "$cur_rel" "$title_value" "$status_value" >> "$gen_draft"
    records_draft=$(( records_draft + 1 ))
    return 0
  fi

  {
    printf '### %s - %s\n\n' "$id" "$title_value"
    printf -- '- source: `%s`\n' "$cur_rel"
    printf -- '- date: %s\n' "$date_value"
    printf -- '- status: %s\n' "$status_value"
    printf -- '- tools: %s\n' "$tools_value"
    printf -- '- tags: %s\n' "$tags_value"
    cap_text "$problem_signature"; printf -- '- problem_signature: %s\n' "$CAP"
    cap_text "${root_cause:--}"; printf -- '- root_cause: %s\n' "$CAP"
    cap_text "${final_fix:--}"; printf -- '- final_fix: %s\n' "$CAP"
    cap_text "${verification:--}"; printf -- '- verification: %s\n' "$CAP"
    cap_text "${reusable_lesson:--}"; printf -- '- reusable_lesson: %s\n' "$CAP"
    cap_text "${follow_up:--}"; printf -- '- follow_up: %s\n\n' "$CAP"
  } >> "$gen_main"
  records_main=$(( records_main + 1 ))
}

# 单次 awk 遍历全部记录：
# - front matter 支持行内数组与多行列表
# - 章节摘要跳过代码围栏，限制行数；不做字节级 substr（macOS awk 会切断多字节字符）
# - 输出 @R（记录开始）与 @F（字段）两类制表符分隔行，由 bash 组装
if [[ -d "$records_dir" ]]; then
  files=()
  while IFS= read -r f; do
    files+=("$f")
  done < <(find "$records_dir" -type f -name '*.md' | sort)

  if [[ ${#files[@]} -gt 0 ]]; then
    while IFS=$'\t' read -r tag field value; do
      case "$tag" in
        '@R')
          emit_record
          cur_rel="$field"
          reset_record_vars
          ;;
        '@F')
          case "$field" in
            id) id="$value" ;;
            title) title_value="$value" ;;
            date) date_value="$value" ;;
            status) status_value="$value" ;;
            tools) tools_value="$value" ;;
            tags) tags_value="$value" ;;
            summary) summary="$value" ;;
            fm_summary) fm_summary="$value" ;;
            signature) signature="$value" ;;
            root) root_cause="$value" ;;
            fix) final_fix="$value" ;;
            verify) verification="$value" ;;
            reuse) reusable_lesson="$value" ;;
            follow) follow_up="$value" ;;
          esac
          ;;
      esac
    done < <(
      # LC_ALL=C：macOS 自带 awk 在 UTF-8 locale 下对含中文的行会报
      # "towc: multibyte conversion failure" 并中断整批记录，这里按字节处理。
      LC_ALL=C awk -v root="$root" '
        function emit(k, v) {
          gsub(/\t/, " ", v)
          print "@F\t" k "\t" v
        }
        function flush_section(   key) {
          if (section == "") return
          key = map[section]
          if (key != "" && out != "") emit(key, out)
          section = ""; out = ""; count = 0
        }
        function emit_fm(   k, v) {
          for (k in fmv) {
            v = fmv[k]
            if (k == "summary") k = "fm_summary"
            emit(k, v)
          }
        }
        function reset() {
          fm = 0; pending = ""; list = ""; fence = 0
          section = ""; out = ""; count = 0
          delete fmv
        }
        BEGIN {
          reset()
          map["一句话结论"] = "summary"
          map["原始现象"] = "signature"
          map["根因分析"] = "root"
          map["最终解决方案"] = "fix"
          map["验证方法"] = "verify"
          map["复用经验"] = "reuse"
          map["后续事项"] = "follow"
          cap["summary"] = 2; cap["signature"] = 3; cap["root"] = 3
          cap["fix"] = 3; cap["verify"] = 2; cap["reuse"] = 3; cap["follow"] = 3
        }
        FNR == 1 {
          if (NR > 1) {
            flush_section()
            emit_fm()
          }
          reset()
          rel = FILENAME
          if (index(rel, root "/") == 1) rel = substr(rel, length(root) + 2)
          print "@R\t" rel
        }
        fm && FNR > 1 && $0 == "---" {
          fm = 0
          if (pending != "") { fmv[pending] = list; pending = ""; list = "" }
          next
        }
        !fm && FNR == 1 && $0 == "---" { fm = 1; next }
        fm {
          if ($0 ~ /^[A-Za-z0-9_-]+:/) {
            if (pending != "") { fmv[pending] = list; pending = ""; list = "" }
            k = $0; sub(/:.*/, "", k)
            v = $0; sub(/^[^:]*:[[:space:]]*/, "", v); gsub(/^"|"$/, "", v)
            if (v ~ /^\[.*\]$/) {
              gsub(/^\[|\]$/, "", v)
              gsub(/"/, "", v)
              gsub(/[[:space:]]*,[[:space:]]*/, ", ", v)
            }
            if (v == "") { pending = k; list = "" } else { fmv[k] = v }
            next
          }
          if ($0 ~ /^[[:space:]]+-[[:space:]]*/) {
            it = $0; sub(/^[[:space:]]+-[[:space:]]*/, "", it); gsub(/^"|"$/, "", it)
            if (pending != "") list = (list == "" ? it : list ", " it)
            next
          }
          next
        }
        /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
        fence { next }
        /^##[[:space:]]+/ {
          flush_section()
          section = $0
          sub(/^##[[:space:]]+/, "", section)
          sub(/[[:space:]]+$/, "", section)
          next
        }
        {
          if (section == "") next
          key = map[section]
          if (key == "") next
          line = $0
          gsub(/^[[:space:]]*([-*]+|[0-9]+\.)[[:space:]]+/, "", line)
          gsub(/^[[:space:]]+/, "", line)
          gsub(/[[:space:]]+$/, "", line)
          if (line == "" || line ~ /^\|/) next
          gsub(/[`*]/, "", line)
          if (count >= cap[key]) next
          if (length(out) >= 300) next
          out = (out == "" ? line : out "; " line)
          count++
        }
        END {
          flush_section()
          emit_fm()
        }
      ' "${files[@]}"
    )
    emit_record
  fi
fi

{
  printf '%s\n\n' "$begin_marker"
  printf '# AI Summary Index\n\n'
  printf 'Generated block. Text outside the PSR markers (for example hand-written notes after the END marker) is preserved on refresh.\n\n'
  printf 'Generated: %s\n\n' "$(date '+%F %T')"
  printf 'Records: %s entries, %s drafts\n\n' "$records_main" "$records_draft"
  printf '## Quick links\n\n'
  printf -- '- Entry protocol: [AI入口.md](AI入口.md)\n'
  printf -- '- Human index: [INDEX.md](INDEX.md)\n'
  printf -- '- Patterns: [patterns/](patterns/README.md)\n'
  printf -- '- Reviews: [reviews/](reviews/README.md)\n\n'
  printf '## Entries\n\n'
  cat "$gen_main"
  printf '## Drafts (not ready for recall)\n\n'
  if [[ -s "$gen_draft" ]]; then
    cat "$gen_draft"
  else
    printf -- '- none\n'
  fi
  printf '\n%s\n' "$end_marker"
} > "$generated"

begin_count=0
end_count=0
begin_line=0
end_line=0
if [[ -f "$target" ]]; then
  begin_count="$(grep -c -F "$begin_marker" "$target" || true)"
  end_count="$(grep -c -F "$end_marker" "$target" || true)"
  begin_line="$(grep -n -F "$begin_marker" "$target" | head -n 1 | cut -d: -f1 || true)"
  end_line="$(grep -n -F "$end_marker" "$target" | head -n 1 | cut -d: -f1 || true)"
fi

if [[ "$begin_count" -eq 1 && "$end_count" -eq 1 && -n "$begin_line" && -n "$end_line" && "$begin_line" -lt "$end_line" ]]; then
  awk -v begin="$begin_marker" -v end="$end_marker" -v generated="$generated" '
    $0 == begin {
      while ((getline line < generated) > 0) {
        print line
      }
      close(generated)
      skip = 1
      next
    }
    $0 == end { skip = 0; next }
    !skip { print }
  ' "$target" > "$merged"
elif [[ "$begin_count" -eq 0 && "$end_count" -eq 0 ]]; then
  # 首次迁移：不把旧内容塞进“手工笔记”（那会让示例出现两份），而是备份后重写。
  if [[ -f "$target" && -s "$target" ]]; then
    backup="${target}.pre-marker.bak"
    cp -p "$target" "$backup"
  fi
  {
    cat "$generated"
    printf '\n## Manual Notes\n\n'
    printf 'Add hand-written notes here. This section is preserved when the generated index is refreshed.\n'
  } > "$merged"
else
  printf '[fail] malformed generated markers in %s (begin=%s, end=%s, begin_line=%s, end_line=%s)\n' \
    "$target" "$begin_count" "$end_count" "${begin_line:-none}" "${end_line:-none}" >&2
  printf 'Fix the markers by hand; the file was left unchanged.\n' >&2
  exit 1
fi

mv "$merged" "$target"
printf 'Updated %s (%s entries, %s drafts)\n' "$target" "$records_main" "$records_draft"
if [[ -n "$backup" ]]; then
  printf 'Previous file backed up to %s\n' "$backup"
fi
