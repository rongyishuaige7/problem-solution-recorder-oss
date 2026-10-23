# Canonical record parser for Problem Solution Recorder.
#
# Every consumer (AI summary index, INDEX.md rebuild, doctor, and the
# knowledge base's own `qs` CLI) must use this file so that one rule set
# governs how records are read.
#
# Invocation:
#   awk -v root=/path/to/kb -v maxlines=3 -f record-fields.awk file1.md file2.md ...
#
# Output (tab separated):
#   @R<TAB>records/2026/2026-01-01-001-topic.md
#   @F<TAB>id<TAB>2026-01-01-001
#   @F<TAB>title<TAB>...
#   ...
#
# Emitted keys: id, title, date, status, severity, tools, tags,
#               fm_summary, summary, signature, root, fix, verify, reuse, follow
#
# Rules:
#   - Front matter is the block between the first two `---` lines of a file.
#   - Inline arrays (`tools: ["a", "b"]`) and multi-line lists
#     (`tools:` followed by `  - a`) are both flattened to `a, b`.
#   - Section text starts at `## <heading>` and stops at the next `## `.
#   - Lines inside ``` or ~~~ fences are kept as content (they are often the
#     verification evidence), but a "##" inside a fence never starts a section.
#   - Table rows (starting with `|`) are ignored; bullets and numbering are stripped.
#   - Each section keeps at most `maxlines` (default 3) lines.
#   - Values are never truncated here; callers apply their own length limits.

function warn(key, reason) {
  print "@W\t" rel "\t" key " " reason
}

function emit(k, v) {
  gsub(/\t/, " ", v)
  print "@F\t" k "\t" v
}

# 把一行正文并入当前章节；围栏内外共用同一套规则。
# 表格行：先保护行内代码，再把单元格分隔符换成空格，最后还原代码。
function strip_table_row(raw,   s, n, i, p, t, code) {
  s = raw
  n = 0
  while (match(s, /`[^`]*`/)) {
    code[++n] = substr(s, RSTART + 1, RLENGTH - 2)
    s = substr(s, 1, RSTART - 1) "\001" n "\001" substr(s, RSTART + RLENGTH)
  }
  gsub(/\|/, " ", s)
  gsub(/[[:space:]]+/, " ", s)
  sub(/^ /, "", s)
  sub(/ $/, "", s)
  for (i = 1; i <= n; i++) {
    t = "\001" i "\001"
    p = index(s, t)
    if (p > 0) s = substr(s, 1, p - 1) code[i] substr(s, p + length(t))
  }
  return s
}

function add_line(raw, in_code,   line, key) {
  if (section == "") return
  key = map[section]
  if (key == "") return
  if (in_code) {
    # 围栏内是代码字面量：只去首尾空白，不解释 Markdown。
    line = raw
    sub(/^[[:space:]]+/, "", line)
    sub(/[[:space:]]+$/, "", line)
  } else if (raw ~ /^[[:space:]]*\|/) {
    # 表格行：保留证据，但代码里的竖线不能被当成分隔符。
    line = strip_table_row(raw)
    if (line ~ /^[-: ]+$/) return
  } else {
    line = strip_line(raw)
  }
  if (line == "") return
  if (count >= maxlines) return
  out = (out == "" ? line : out "; " line)
  if (key == "follow") items = (items == "" ? line : items "\036" line)
  count++
}

function flush_section(   key) {
  if (section == "") return
  key = map[section]
  if (key != "" && out != "") emit(key, out)
  # 后续事项逐条保留（含 [ ]/[x]），供复盘聚合使用。
  if (key == "follow" && items != "") emit("follow_items", items)
  section = ""; out = ""; count = 0; items = ""
}

function emit_fm(   k, v) {
  for (k in fmv) {
    v = fmv[k]
    if (k == "summary") k = "fm_summary"
    emit(k, v)
  }
}

function reset() {
  fm = 0; pending = ""; list = ""; fence = ""; fence_len = 0; block = 0
  section = ""; out = ""; count = 0; items = ""
  delete fmv
}

# 与 web/generate-data.js 的 cleanMarkdown 保持同一套清理规则：
# 去列表符号、链接只留文本、去行内代码/粗体标记；单个 * 属于内容，保留。
function strip_line(s,   n, i, p, t, code) {
  # 行内代码先占位：其中的 ** 属于代码字面量，不能被当成粗体标记。
  n = 0
  while (match(s, /`[^`]*`/)) {
    code[++n] = substr(s, RSTART + 1, RLENGTH - 2)
    s = substr(s, 1, RSTART - 1) "\001" n "\001" substr(s, RSTART + RLENGTH)
  }

  gsub(/^[[:space:]]*([-*]+|[0-9]+\.)[[:space:]]+/, "", s)
  gsub(/^[[:space:]]+/, "", s)
  gsub(/[[:space:]]+$/, "", s)

  while (match(s, /\[[^]]*\]\([^)]*\)/)) {
    label = substr(s, RSTART + 1, RLENGTH - 2)
    sub(/\]\(.*/, "", label)
    s = substr(s, 1, RSTART - 1) label substr(s, RSTART + RLENGTH)
  }

  # 只有成对的 **粗体** 去标记；**kwargs 这类代码保持原样。
  while (match(s, /\*\*[^*]+\*\*/)) {
    inner = substr(s, RSTART + 2, RLENGTH - 4)
    s = substr(s, 1, RSTART - 1) inner substr(s, RSTART + RLENGTH)
  }

  for (i = 1; i <= n; i++) {
    t = "\001" i "\001"
    p = index(s, t)
    if (p > 0) s = substr(s, 1, p - 1) code[i] substr(s, p + length(t))
  }
  return s
}

BEGIN {
  reset()
  if (maxlines == "") maxlines = 3
  map["一句话结论"] = "summary"
  map["原始现象"] = "signature"
  map["根因分析"] = "root"
  map["最终解决方案"] = "fix"
  map["验证方法"] = "verify"
  map["复用经验"] = "reuse"
  map["后续事项"] = "follow"
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
  if (block) {
    if ($0 ~ /^[[:space:]]/) next
    block = 0
  }
  if ($0 ~ /^[A-Za-z0-9_-]+:/) {
    if (pending != "") { fmv[pending] = list; pending = ""; list = "" }
    k = $0; sub(/:.*/, "", k)
    v = $0; sub(/^[^:]*:[[:space:]]*/, "", v); gsub(/^"|"$/, "", v)
    if (v ~ /^\[.*\]$/) {
      gsub(/^\[|\]$/, "", v)
      gsub(/"/, "", v)
      gsub(/[[:space:]]*,[[:space:]]*/, ", ", v)
    }
    if (v == "|" || v == ">") {
      # 块标量（| / >）不是本格式支持的写法：给出字段级诊断，按空值处理。
      warn(k, "block-scalar")
      block = 1
      next
    }
    if (v == "") { pending = k; list = "" } else { fmv[k] = v }
    next
  }
  if ($0 ~ /^[[:space:]]+-[[:space:]]*/) {
    it = $0; sub(/^[[:space:]]+-[[:space:]]*/, "", it); gsub(/^"|"$/, "", it)
    if (pending != "") list = (list == "" ? it : list ", " it)
    next
  }
  if ($0 ~ /^[[:space:]]+[^[:space:]]/ && pending != "") {
    # 嵌套映射等写法不支持：诊断一次，避免静默变成空值。
    warn(pending, "nested-map")
    pending = ""
    list = ""
    next
  }
  next
}

# 围栏必须记录开围栏的字符与长度：反引号围栏里的 ~~~ 文本不是关闭符。
/^[[:space:]]*(```+|~~~+)/ {
  line = $0
  sub(/^[[:space:]]+/, "", line)
  ch = substr(line, 1, 1)
  n = 0
  while (substr(line, n + 1, 1) == ch) n++
  if (fence == "") {
    fence = ch
    fence_len = n
  } else if (ch == fence && n >= fence_len) {
    fence = ""
    fence_len = 0
  }
  next
}
fence != "" { add_line($0, 1); next }

/^##[[:space:]]+/ {
  flush_section()
  section = $0
  sub(/^##[[:space:]]+/, "", section)
  sub(/[[:space:]]+$/, "", section)
  next
}

{ add_line($0, 0) }

END {
  flush_section()
  emit_fm()
}
