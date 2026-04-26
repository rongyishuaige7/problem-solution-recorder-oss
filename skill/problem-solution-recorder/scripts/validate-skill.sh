#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
SKILL_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd -P)"

QUIET=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -q|--quiet) QUIET=1 ;;
    -h|--help)
      printf 'Usage: validate-skill.sh [--quiet]\n'
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      exit 2
      ;;
  esac
  shift
done

log_ok() {
  if [[ "$QUIET" -eq 0 ]]; then
    printf '%s\n' "$*"
  fi
}

fail() {
  printf '[fail] %s\n' "$*" >&2
  exit 1
}

[[ -f "$SKILL_DIR/SKILL.md" ]] || fail "missing SKILL.md"
grep -Eq '^name:[[:space:]]*problem-solution-recorder$' "$SKILL_DIR/SKILL.md" || fail "SKILL.md missing required name"
grep -Eq '^description:[[:space:]]*.+' "$SKILL_DIR/SKILL.md" || fail "SKILL.md missing description"
grep -Eq '^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+' "$SKILL_DIR/SKILL.md" || fail "SKILL.md missing semver version"

desc_line="$(awk '/^description:/{if (match($0, /^description:[[:space:]]*/)) {print substr($0, RLENGTH+1); exit}}' "$SKILL_DIR/SKILL.md")"
desc_len="${#desc_line}"
if [[ "$desc_len" -gt 1024 ]]; then
  fail "SKILL.md description exceeds 1024 characters (length=$desc_len)"
fi

[[ -f "$SKILL_DIR/references/repository-protocol.md" ]] || fail "missing references/repository-protocol.md"
for agent in openai.yaml claude.yaml cursor.yaml openclaw.yaml; do
  [[ -f "$SKILL_DIR/agents/$agent" ]] || fail "missing agents/$agent"
done
[[ -d "$SKILL_DIR/assets/minimal-knowledge-base" ]] || fail "missing assets/minimal-knowledge-base"

for script in resolve-kb-root.sh init-kb.sh doctor-local.sh validate-skill.sh install.sh print-prompt.sh new-record.sh update-ai-summary-index.sh smoke-test.sh; do
  [[ -x "$SKILL_DIR/scripts/$script" ]] || fail "missing executable scripts/$script"
done

for template in "问题记录模板.md" "快记模板.md" "方法论模板.md" "日报复盘模板.md" "周报复盘模板.md"; do
  [[ -f "$SKILL_DIR/assets/minimal-knowledge-base/_templates/$template" ]] || fail "missing template $template"
done

for file in "AI入口.md" "AI记录提示词.md" "AI工具记录规则.md" "INDEX.md" "AI_SUMMARY_INDEX.md"; do
  [[ -f "$SKILL_DIR/assets/minimal-knowledge-base/$file" ]] || fail "missing minimal knowledge base file $file"
done

# Scan only paths where private home dirs would be accidental; exclude agents/ (example tool paths).
: > /tmp/problem-solution-recorder-private-paths.txt
grep -R --line-number \
  --exclude='validate-skill.sh' \
  --exclude-dir='.git' \
  --exclude='.psr-installed-from' \
  -E '/home/[A-Za-z0-9._-]+|/Users/[A-Za-z0-9._-]+' "$SKILL_DIR/references" "$SKILL_DIR/scripts" "$SKILL_DIR/assets" "$SKILL_DIR/SKILL.md" 2>/dev/null >> /tmp/problem-solution-recorder-private-paths.txt || true
grep -vE 'SKILL\.md:.*github\.com' /tmp/problem-solution-recorder-private-paths.txt > /tmp/problem-solution-recorder-private-paths-filtered.txt || true
if [[ -s /tmp/problem-solution-recorder-private-paths-filtered.txt ]]; then
  cat /tmp/problem-solution-recorder-private-paths-filtered.txt >&2
  fail "private absolute home paths found (scan: references, scripts, assets, SKILL.md)"
fi

if grep -R --line-number \
  --exclude='validate-skill.sh' \
  --exclude-dir='.git' \
  --exclude='.psr-installed-from' \
  -E '(real-secret-value|sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,})' "$SKILL_DIR" >/tmp/problem-solution-recorder-secret-patterns.txt; then
  cat /tmp/problem-solution-recorder-secret-patterns.txt >&2
  fail "potential secret pattern found"
fi

log_ok '[ok] public skill structure checks passed'
