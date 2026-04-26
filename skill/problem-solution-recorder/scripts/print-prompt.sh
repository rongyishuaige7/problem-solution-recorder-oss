#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Print copyable prompts for AI tools.

Usage:
  print-prompt.sh [global-rule|record|search|review|hook]

Default:
  global-rule
EOF
}

mode="${1:-global-rule}"

case "$mode" in
  -h|--help)
    usage
    exit 0
    ;;
  global-rule)
    cat <<'EOF'
Use the Problem Solution Recorder workflow when a solved issue is worth preserving.

Before reading or writing records, resolve the knowledge base root in this order:
1. PROBLEM_SOLUTION_KB_ROOT
2. .problem-solution-root in the current project or a parent directory
3. ~/.config/problem-solution-recorder/root
4. Ask me for the path, or offer to initialize a new knowledge base

When recording a solved issue:
- Read AI入口.md and _templates/问题记录模板.md first.
- Create records/YYYY/YYYY-MM-DD-NNN-short-topic.md.
- Update INDEX.md and AI_SUMMARY_INDEX.md.
- Add or update patterns/ if the method is reusable.
- Redact API keys, tokens, cookies, passwords, private keys, authorization codes, session IDs, and bearer tokens as [REDACTED].

After completing a debugging or setup task, silently decide whether it has future value. If it does, ask:
"这个问题值得记录到问题解决知识库吗？"
EOF
    ;;
  record)
    cat <<'EOF'
Please record this solved issue in my Problem Solution Recorder knowledge base.

Requirements:
- Resolve the knowledge base root first.
- Follow _templates/问题记录模板.md.
- Preserve original symptom, environment/config, timeline, failed attempts, root cause, final solution, verification, reusable lessons, and follow-ups.
- Update INDEX.md and AI_SUMMARY_INDEX.md.
- Add a pattern when the method is reusable.
- Hide API keys, tokens, cookies, passwords, private keys, and other secrets.
EOF
    ;;
  search)
    cat <<'EOF'
Please search my Problem Solution Recorder knowledge base for relevant past issues.

Search order:
1. AI_SUMMARY_INDEX.md
2. patterns/
3. relevant records/YYYY/*.md
4. reviews/ only for trend or recap questions

Summarize the matching records and link the source files you used.
EOF
    ;;
  review)
    cat <<'EOF'
Please generate a daily or weekly review from my Problem Solution Recorder knowledge base.

Use AI_SUMMARY_INDEX.md first, then open only records that are needed for detail. Include repeated issue types, reusable methods, unresolved follow-ups, and the next actions that would reduce future debugging time.
EOF
    ;;
  hook)
    cat <<'EOF'
Completion hook rule:

At the end of every debugging, setup, tool integration, dependency, permission, API, MCP, build, test, or AI-tool behavior task, silently score whether the solved issue is worth preserving.

Strong signals:
- More than three investigation steps
- Clear symptom, root cause, and final fix
- A failed attempt or misleading path
- Non-trivial local environment, config, permission, auth, API, MCP, dependency, or adapter behavior
- The method is likely to be reused

If at least two strong signals are present and I did not opt out, ask:
"这个问题值得记录到问题解决知识库吗？"

If I explicitly asked to record it, write the record without asking again.
EOF
    ;;
  *)
    printf 'Unknown prompt mode: %s\n' "$mode" >&2
    usage >&2
    exit 2
    ;;
esac
