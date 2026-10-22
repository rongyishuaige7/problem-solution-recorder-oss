#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$( ( unset CDPATH; cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P ) )"

usage() {
  cat <<'EOF'
Measure summary-index and index-rebuild cost on a synthetic knowledge base.

Usage:
  perf-check.sh [record-count]

Targets (documented, not enforced here):
  100 records: cold run under 3s, repeat run under 1s, repeat is byte-identical.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

count="${1:-100}"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/psr-perf.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

now_ms() {
  if command -v perl >/dev/null 2>&1; then
    perl -MTime::HiRes=time -e 'printf "%.0f\n", time * 1000'
  else
    printf '%s000\n' "$(date +%s)"
  fi
}

"$SCRIPT_DIR/init-kb.sh" "$tmp/kb" >/dev/null
mkdir -p "$tmp/kb/records/2026"
for i in $(seq 1 "$count"); do
  day=$(( (i % 28) + 1 ))
  printf -- '---\ntitle: "perf %s"\ndate: 2026-06-%02d\nstatus: solved\ntools: [codex, bash]\ntags: [perf]\nsummary: "第 %s 条"\n---\n\n# perf %s\n\n## 一句话结论\n\n第 %s 条结论。\n\n## 根因分析\n\n根因 %s。\n' \
    "$i" "$day" "$i" "$i" "$i" "$i" > "$tmp/kb/records/2026/2026-06-$(printf '%02d' "$day")-$(printf '%03d' "$i")-perf-$i.md"
done

start="$(now_ms)"
"$SCRIPT_DIR/update-ai-summary-index.sh" "$tmp/kb" >/dev/null
cold=$(( $(now_ms) - start ))

cp "$tmp/kb/AI_SUMMARY_INDEX.md" "$tmp/before"
start="$(now_ms)"
"$SCRIPT_DIR/update-ai-summary-index.sh" "$tmp/kb" >/dev/null
warm=$(( $(now_ms) - start ))
cmp -s "$tmp/before" "$tmp/kb/AI_SUMMARY_INDEX.md" && identical=yes || identical=no

start="$(now_ms)"
"$SCRIPT_DIR/rebuild-index.sh" "$tmp/kb" >/dev/null
rebuild=$(( $(now_ms) - start ))

printf 'records:      %s\n' "$count"
printf 'summary cold: %s ms\n' "$cold"
printf 'summary warm: %s ms (byte-identical: %s)\n' "$warm" "$identical"
printf 'rebuild:      %s ms\n' "$rebuild"

status=0
[[ "$cold" -lt 3000 ]] || { printf '[warn] cold run exceeded 3000ms\n' >&2; status=1; }
[[ "$warm" -lt 1000 ]] || { printf '[warn] warm run exceeded 1000ms\n' >&2; status=1; }
[[ "$identical" == "yes" ]] || { printf '[warn] warm run was not byte-identical\n' >&2; status=1; }
exit "$status"
