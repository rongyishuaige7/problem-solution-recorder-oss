#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$( ( unset CDPATH; cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P ) )"
RESOLVE="$SCRIPT_DIR/resolve-kb-root.sh"

root="$("$RESOLVE" "${1:-}")"
records_dir="$root/records"
target="$root/AI_SUMMARY_INDEX.md"
tmp="${target}.tmp"
generated_tmp="${target}.generated.tmp"

begin_marker='<!-- PSR:BEGIN GENERATED -->'
end_marker='<!-- PSR:END GENERATED -->'

front_value() {
  local file="$1"
  local key="$2"
  awk -v key="$key" '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { exit }
    fm && index($0, key ":") == 1 {
      sub("^[^:]+:[[:space:]]*", "", $0)
      gsub(/^"/, "", $0)
      gsub(/"$/, "", $0)
      print
      exit
    }
  ' "$file"
}

heading_title() {
  awk '/^# / { sub(/^# /, ""); print; exit }' "$1"
}

section_text() {
  local file="$1"
  local section="$2"
  awk -v section="$section" '
    $0 == "## " section { capture = 1; next }
    capture && /^##[[:space:]]/ { exit }
    capture { print }
  ' "$file" |
    sed -e 's/^[[:space:]-]*//' -e '/^[[:space:]]*$/d' |
    tr '\n' ' ' |
    sed -E 's/[[:space:]]+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//'
}

{
  printf '%s\n' "$begin_marker"
  printf '\n'
  printf '# AI Summary Index\n\n'
  printf 'Use this generated section as the first stop for AI recall.\n\n'
  printf '## Entries\n\n'

  if [[ -d "$records_dir" ]]; then
    while IFS= read -r file; do
      rel="${file#"$root"/}"
      date_value="$(front_value "$file" date)"
      title_value="$(front_value "$file" title)"
      status_value="$(front_value "$file" status)"
      tools_value="$(front_value "$file" tools)"
      tags_value="$(front_value "$file" tags)"

      [[ -n "$date_value" ]] || date_value="$(basename "$file" | cut -d- -f1-3)"
      [[ -n "$title_value" ]] || title_value="$(heading_title "$file")"
      [[ -n "$status_value" ]] || status_value="unknown"
      [[ -n "$tools_value" ]] || tools_value="[]"
      [[ -n "$tags_value" ]] || tags_value="[]"
      [[ -n "$title_value" ]] || title_value="$rel"

      problem_signature="$(section_text "$file" "原始现象")"
      root_cause="$(section_text "$file" "根因分析")"
      final_fix="$(section_text "$file" "最终解决方案")"
      verification="$(section_text "$file" "验证方法")"
      reusable_lesson="$(section_text "$file" "复用经验")"
      follow_up="$(section_text "$file" "后续事项")"

      printf '### %s - %s\n\n' "$date_value" "$title_value"
      printf -- "- source: \`%s\`\n" "$rel"
      printf -- '- status: %s\n' "$status_value"
      printf -- '- tools: %s\n' "$tools_value"
      printf -- '- tags: %s\n' "$tags_value"
      printf -- '- problem_signature: %s\n' "${problem_signature:-"-"}"
      printf -- '- root_cause: %s\n' "${root_cause:-"-"}"
      printf -- '- final_fix: %s\n' "${final_fix:-"-"}"
      printf -- '- verification: %s\n' "${verification:-"-"}"
      printf -- '- reusable_lesson: %s\n' "${reusable_lesson:-"-"}"
      printf -- '- follow_up: %s\n\n' "${follow_up:-"-"}"
    done < <(find "$records_dir" -type f -name '*.md' | sort)
  fi
  printf '%s\n' "$end_marker"
} > "$generated_tmp"

if [[ -f "$target" ]] && grep -Fq "$begin_marker" "$target" && grep -Fq "$end_marker" "$target"; then
  awk -v begin="$begin_marker" -v end="$end_marker" -v generated="$generated_tmp" '
    $0 == begin {
      while ((getline line < generated) > 0) {
        print line
      }
      close(generated)
      in_generated = 1
      next
    }
    in_generated && $0 == end {
      in_generated = 0
      next
    }
    !in_generated {
      print
    }
  ' "$target" > "$tmp"
else
  {
    cat "$generated_tmp"
    printf '\n## Manual Notes\n\n'
    if [[ -f "$target" ]]; then
      printf 'Previous content preserved during migration to generated markers. Edit this section freely; it is preserved when the generated index is refreshed.\n\n'
      cat "$target"
    else
      printf 'Add hand-written notes here. This section is preserved when the generated index is refreshed.\n'
    fi
  } > "$tmp"
fi

mv "$tmp" "$target"
rm -f "$generated_tmp"
printf 'Updated %s\n' "$target"
