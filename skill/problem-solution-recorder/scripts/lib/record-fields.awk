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
#   - Lines inside ``` or ~~~ fences are ignored.
#   - Table rows (starting with `|`) are ignored; bullets and numbering are stripped.
#   - Each section keeps at most `maxlines` (default 3) lines.
#   - Values are never truncated here; callers apply their own length limits.

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

function strip_line(s) {
  gsub(/^[[:space:]]*([-*]+|[0-9]+\.)[[:space:]]+/, "", s)
  gsub(/^[[:space:]]+/, "", s)
  gsub(/[[:space:]]+$/, "", s)
  gsub(/[`*]/, "", s)
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
  line = strip_line($0)
  if (line == "" || line ~ /^\|/) next
  if (count >= maxlines) next
  out = (out == "" ? line : out "; " line)
  count++
}

END {
  flush_section()
  emit_fm()
}
