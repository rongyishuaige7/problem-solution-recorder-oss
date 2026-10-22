#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$( ( unset CDPATH; cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P ) )"
RESOLVE="$SCRIPT_DIR/resolve-kb-root.sh"
PARSER="$SCRIPT_DIR/lib/record-fields.awk"

root="$("$RESOLVE" "${1:-}")"
records_dir="$root/records"
target="$root/AI_SUMMARY_INDEX.md"

begin_marker='<!-- PSR:BEGIN GENERATED -->'
end_marker='<!-- PSR:END GENERATED -->'

[[ -f "$PARSER" ]] || {
  printf 'Missing record parser: %s\n' "$PARSER" >&2
  exit 1
}

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/psr-summary.XXXXXX")"
gen_main="$tmp_dir/main"
gen_draft="$tmp_dir/draft"
generated="$tmp_dir/generated"
merged="$tmp_dir/merged"
stream="$tmp_dir/stream"
awk_err="$tmp_dir/awk.err"
backup=""

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

: > "$gen_main"
: > "$gen_draft"

records_main=0
records_draft=0
cur_rel=""
BT='`'
CAP=""

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

cap_text() {
  CAP="$1"
  if [[ ${#CAP} -gt 300 ]]; then
    CAP="${CAP:0:297}…"
  fi
}

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
    printf -- '- %s%s%s — %s (status: %s)\n' "$BT" "$cur_rel" "$BT" "$title_value" "$status_value" >> "$gen_draft"
    records_draft=$(( records_draft + 1 ))
    return 0
  fi

  {
    printf '### %s - %s\n\n' "$id" "$title_value"
    printf -- '- source: %s%s%s\n' "$BT" "$cur_rel" "$BT"
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

files=()
if [[ -d "$records_dir" ]]; then
  while IFS= read -r f; do
    files+=("$f")
  done < <(find "$records_dir" -type f -name '*.md' | sort)
fi

# 先把全部记录解析到一个临时文件，再读它：
# 进程替换里的读取失败不会传回主流程，旧实现因此会在解析出错时覆盖索引并返回成功。
if [[ ${#files[@]} -gt 0 ]]; then
  set +e
  LC_ALL=C awk -v root="$root" -v maxlines=3 -f "$PARSER" "${files[@]}" > "$stream" 2> "$awk_err"
  awk_rc=$?
  set -e

  if [[ "$awk_rc" -ne 0 ]]; then
    cat "$awk_err" >&2
    printf '[fail] could not read every record (awk exit %s); %s left unchanged.\n' "$awk_rc" "$target" >&2
    exit 1
  fi

  parsed_records="$(grep -c '^@R' "$stream" || true)"
  expected_records=0
  for f in "${files[@]}"; do
    [[ -s "$f" ]] && expected_records=$(( expected_records + 1 ))
  done
  if [[ "$parsed_records" -ne "$expected_records" ]]; then
    cat "$awk_err" >&2
    printf '[fail] parsed %s of %s non-empty records; %s left unchanged.\n' "$parsed_records" "$expected_records" "$target" >&2
    exit 1
  fi
  if [[ "$expected_records" -ne "${#files[@]}" ]]; then
    printf '[warn] skipped %s empty record file(s)\n' "$(( ${#files[@]} - expected_records ))" >&2
  fi

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
  done < "$stream"
  emit_record
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
