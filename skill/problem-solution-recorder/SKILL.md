---
name: problem-solution-recorder
version: 0.1.0
license: MIT
description: Maintain a configurable problem-solution knowledge base for solved incidents, debugging sessions, reusable troubleshooting patterns, and periodic reviews. Use when the user asks to record, archive, review, summarize, search, or preserve a solved issue; when a multi-step debugging task involving CLI tools, MCP, APIs, permissions, configs, dependencies, build errors, adapters, or AI tool behavior is completed; or when the user wants to reuse lessons from previous incidents.
metadata:
  openclaw:
    homepage: "https://github.com/rongyishuaige7/problem-solution-recorder-oss"
    emoji: "📋"
    requires:
      bins:
        - bash
        - find
        - awk
        - sed
        - grep
---

# Problem Solution Recorder

Use this skill to maintain a problem-solution knowledge base outside the skill. The skill is a workflow wrapper; the user's live Markdown repository remains the source of truth.

## Resolve The Knowledge Base

Before writing, searching, or summarizing, resolve the knowledge base root in this order:

1. Use `PROBLEM_SOLUTION_KB_ROOT` if set.
2. Use `.problem-solution-root` in the current project or a parent directory if present.
3. Use `$XDG_CONFIG_HOME/problem-solution-recorder/root` or `~/.config/problem-solution-recorder/root` if present.
4. If none is configured, ask the user for the knowledge base path or offer to initialize one.

The helper script can resolve the root:

```bash
./scripts/resolve-kb-root.sh
```

After resolving the root, read:

```text
$PROBLEM_SOLUTION_KB_ROOT/AI入口.md
```

Treat that file as the source of truth for the user's current repository structure, paths, templates, indexes, review files, and safety rules.

Read `references/repository-protocol.md` when you need the detailed generic protocol.

## New Record Workflow

When adding a solved issue:

1. Read `$PROBLEM_SOLUTION_KB_ROOT/AI入口.md`.
2. Read `$PROBLEM_SOLUTION_KB_ROOT/_templates/问题记录模板.md`.
3. Create a record under `$PROBLEM_SOLUTION_KB_ROOT/records/YYYY/`.
4. Use filename format `YYYY-MM-DD-NNN-short-topic.md`.
5. Fill the required sections: `一句话结论`, `原始现象`, `环境与关键配置`, `排查时间线`, `失败尝试`, `根因分析`, `最终解决方案`, `验证方法`, `复用经验`, `后续事项`.
6. Update `$PROBLEM_SOLUTION_KB_ROOT/INDEX.md`.
7. Update `$PROBLEM_SOLUTION_KB_ROOT/AI_SUMMARY_INDEX.md`, or run the repository CLI if available.
8. If the solution is reusable beyond one incident, add or update a pattern under `$PROBLEM_SOLUTION_KB_ROOT/patterns/`.
9. Redact secrets before writing.

If the user explicitly asks to record, do not ask again. If the user did not ask but the solved issue is clearly reusable, ask briefly before writing.

## Preferred Commands

Use the bundled helper scripts when the repository does not provide a stronger native CLI:

```bash
./scripts/new-record.sh "Issue title"
./scripts/update-ai-summary-index.sh
./scripts/print-prompt.sh global-rule
./scripts/doctor-local.sh
./scripts/check-kb.sh
```

Use the repository CLI when available and more capable:

```bash
"$PROBLEM_SOLUTION_KB_ROOT/bin/qs" new "Issue title"
"$PROBLEM_SOLUTION_KB_ROOT/bin/qs" ai-index
"$PROBLEM_SOLUTION_KB_ROOT/bin/qs" check
"$PROBLEM_SOLUTION_KB_ROOT/bin/qs" today --force
"$PROBLEM_SOLUTION_KB_ROOT/bin/qs" week --force
```

If the CLI is unavailable, edit the Markdown files directly.

## Completion Hook

After completing a debugging, setup, MCP/API integration, dependency, permission, build, test, or AI-tool-behavior task, silently judge whether the solution has future value.

Ask to record only when at least two strong signals are present:

- More than three investigation steps.
- Clear symptom, root cause, and final fix.
- A failed attempt or misleading path.
- Non-trivial local environment, config, permission, auth, dependency, adapter, API, MCP, or AI-tool behavior.
- The method is likely to be reused.

Ask:

```text
这个问题值得记录到问题解决知识库吗？
```

If the user explicitly asked to record, do not ask again.

## Search Workflow

When the user asks about past issues:

1. Read `$PROBLEM_SOLUTION_KB_ROOT/AI_SUMMARY_INDEX.md` first.
2. Search with `rg` or the repository search command.
3. Open only the relevant full records from `records/`.
4. Prefer summarized reusable lessons over reading every record.

## Initialize A New Knowledge Base

When the user wants a new repository, run:

```bash
./scripts/init-kb.sh /path/to/problem-solution-kb
```

Then tell the user to configure:

```bash
export PROBLEM_SOLUTION_KB_ROOT="/path/to/problem-solution-kb"
```

or create `.problem-solution-root` in the project.

For copyable prompts and global-rule snippets, use:

```bash
./scripts/print-prompt.sh global-rule
./scripts/print-prompt.sh hook
```

## Localization

The bundled minimal knowledge base and helper scripts (`new-record.sh`, `update-ai-summary-index.sh`) use Chinese Markdown headings for record sections (for example `一句话结论`, `原始现象`). That is an intentional default for this template. To use English-only headings, replace the templates under `_templates/` and adjust the section names in `scripts/update-ai-summary-index.sh` if you still want automatic AI index extraction.

## Safety

Never write real API keys, tokens, cookies, passwords, private keys, authorization codes, session secrets, or bearer tokens.

Use `[REDACTED]` for secret values. It is OK to record variable names like `EXAMPLE_API_KEY`, but not their values.

Before finalizing a write, run the repository checker if available:

```bash
"$PROBLEM_SOLUTION_KB_ROOT/bin/qs" check
```

If no repository-native checker exists, run:

```bash
./scripts/check-kb.sh "$PROBLEM_SOLUTION_KB_ROOT"
```

If write permission is unavailable, output the complete Markdown record and the exact index entries that should be added.
