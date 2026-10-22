# shellcheck shell=bash
# INDEX.md helpers: schema detection, cell escaping, row building, ordered
# insertion, and escape-aware row parsing.
#
# The human index exists in two shapes:
#   6 columns: | Date | Title | Status | Tools | Tags | Record |
#   7 columns: | ID | 日期 | 标题 | 工具/系统 | 状态 | 关键根因 | 记录 |
#
# A 7-column index may carry hand-written root causes; rebuild-index.sh merges
# those by ID instead of overwriting them.

psr_index_schema() {
  local index="$1"
  if [[ -f "$index" ]] && grep -qE '^\|[[:space:]]*ID[[:space:]]*\|' "$index" && grep -q '关键根因' "$index"; then
    printf '7'
  else
    printf '6'
  fi
}

psr_index_escape() {
  local value="$1"
  value="$(printf '%s' "$value" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//')"
  value="${value//\\/\\\\}"
  value="${value//|/\\|}"
  printf '%s' "$value"
}

psr_index_row() {
  local schema="$1"
  local id="$2"
  local date="$3"
  local title="$4"
  local tools="$5"
  local tags="$6"
  local status="$7"
  local root_cause="$8"
  local rel="$9"

  local t d i g r s
  t="$(psr_index_escape "$title")"
  d="$(psr_index_escape "$date")"
  i="$(psr_index_escape "$tools")"
  g="$(psr_index_escape "$tags")"
  r="$(psr_index_escape "$root_cause")"
  s="$(psr_index_escape "$status")"

  if [[ "$schema" == "7" ]]; then
    printf '| %s | %s | %s | %s | %s | %s | [查看](%s) |' "$id" "$d" "$t" "$i" "$s" "$r" "$rel"
  else
    printf '| %s | %s | %s | %s | %s | [%s](%s) |' "$d" "$t" "$s" "$i" "$g" "$rel" "$rel"
  fi
}

# Insert a row in date-descending order (first row whose key is smaller wins;
# a key older than every row goes to the end).
psr_index_insert() {
  local index="$1"
  local row="$2"
  local key="$3"
  local insert_after tmp

  insert_after="$(awk -v key="$key" '
    /^\|[[:space:]]*[0-9]{4}-[0-9]{2}-[0-9]{2}/ {
      line = $0
      sub(/^\|[[:space:]]*/, "", line)
      sub(/[[:space:]]*\|.*/, "", line)
      if (!first) { first = NR; first_id = line }
      last = NR; last_id = line
      if (!found && line < key) { print NR - 1; found = 1; exit }
    }
    END {
      if (found) exit
      if (!first) { print 0; exit }
      if (key > first_id) { print first - 1; exit }
      print last
    }
  ' "$index")"

  if [[ -z "$insert_after" || "$insert_after" -eq 0 ]]; then
    insert_after="$(grep -nE '^\|[-:| ]+\|$' "$index" | head -n 1 | cut -d: -f1 || true)"
  fi

  if [[ -z "$insert_after" ]]; then
    printf '%s\n' "$row" >> "$index"
    return 0
  fi

  tmp="$(mktemp "${TMPDIR:-/tmp}/psr-index-insert.XXXXXX")"
  # 用环境变量传行内容：awk -v 会把 \| 解释成 |，破坏 Markdown 转义。
  PSR_INDEX_ROW="$row" awk -v n="$insert_after" '
    NR == n { print; print ENVIRON["PSR_INDEX_ROW"]; next }
    { print }
  ' "$index" > "$tmp"
  mv "$tmp" "$index"
}

# Emit existing rows as TSV: id, date, title, tools, status, root, rel.
# Escaped pipes are handled; cells keep their original `\|` escaping so that
# re-emitting them is byte-stable.
psr_index_rows() {
  local index="$1"
  [[ -f "$index" ]] || return 0
  awk '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    {
      row = $0
      gsub(/\\\|/, "\001", row)
      if (row ~ /^\|[[:space:]]*ID[[:space:]]*\|/) { schema = 7; next }
      if (row ~ /^\|[[:space:]]*Date[[:space:]]*\|/) { schema = 6; next }
      if (row !~ /^\|[[:space:]]*[0-9]{4}-[0-9]{2}-[0-9]{2}/) next
      n = split(row, f, "|")
      for (i = 1; i <= n; i++) f[i] = trim(f[i])
      if (schema == 7) { id = f[2]; date = f[3]; title = f[4]; tools = f[5]; status = f[6]; root = f[7]; link = f[8] }
      else { id = ""; date = f[2]; title = f[3]; status = f[4]; tools = f[5]; root = "-"; link = f[7] }
      if (!match(link, /\(([^)]+)\)/)) next
      rel = substr(link, RSTART + 1, RLENGTH - 2)
      # 恢复成原始字符；写回时由 psr_index_row/psr_index_escape 统一转义一次。
      gsub(/\001/, "|", id); gsub(/\001/, "|", date); gsub(/\001/, "|", title)
      gsub(/\001/, "|", tools); gsub(/\001/, "|", status); gsub(/\001/, "|", root)
      printf "%s\037%s\037%s\037%s\037%s\037%s\037%s\n", id, date, title, tools, status, root, rel
    }
  ' "$index"
}

# ---- status vocabulary -----------------------------------------------------
# Machine status lives in the record front matter (draft/investigating/solved/
# workaround/unresolved). The index cell may be a human label such as
# "已解决（审计）"; tool-owned cells are "草稿"/"draft"/"待填写"/"-".

psr_status_label() {
  local machine="$1"
  local schema="$2"
  if [[ "$schema" == "7" ]]; then
    case "$machine" in
      draft) printf '草稿' ;;
      investigating) printf '调查中' ;;
      solved) printf '已解决' ;;
      workaround) printf '临时方案' ;;
      unresolved) printf '未解决' ;;
      *) printf '%s' "$machine" ;;
    esac
  else
    printf '%s' "$machine"
  fi
}

psr_status_machine() {
  local cell="$1"
  case "$cell" in
    solved|已解决*) printf 'solved' ;;
    workaround|临时方案*|变通*) printf 'workaround' ;;
    investigating|调查中*|实施中*) printf 'investigating' ;;
    unresolved|未解决*) printf 'unresolved' ;;
    draft|草稿*) printf 'draft' ;;
    *) printf '' ;;
  esac
}

psr_status_is_tool_owned() {
  case "$1" in
    ""|"-"|"待填写"|draft|草稿) return 0 ;;
  esac
  return 1
}

# Replace the row matching <id> (7-column) or <rel> (6-column) with new_row.
psr_index_replace_row() {
  local index="$1"
  local id="$2"
  local rel="$3"
  local row="$4"
  local tmp

  tmp="$(mktemp "${TMPDIR:-/tmp}/psr-index-replace.XXXXXX")"
  PSR_NEW_ROW="$row" awk -v idkey="$id" -v relkey="$rel" '
    BEGIN { done = 0 }
    {
      if (!done) {
        probe = $0
        gsub(/\\\|/, "\001", probe)
        if (probe ~ /^\|[[:space:]]*[0-9]{4}-[0-9]{2}-[0-9]{2}/) {
          n = split(probe, f, "|")
          idv = f[2]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", idv)
          # 链接列的位置随 6/7 列而变，按“含 ](…)”从后往前找，避免列数误判。
          linkv = ""
          for (i = n; i >= 1; i--) {
            if (f[i] ~ /\]\([^)]+\)/) { linkv = f[i]; break }
          }
          if (match(linkv, /\(([^)]+)\)/)) {
            relv = substr(linkv, RSTART + 1, RLENGTH - 2)
            if ((idkey != "" && idv == idkey) || (idkey == "" && relv == relkey)) {
              print ENVIRON["PSR_NEW_ROW"]
              done = 1
              next
            }
          }
        }
      }
      print
    }
  ' "$index" > "$tmp"
  mv "$tmp" "$index"
}
