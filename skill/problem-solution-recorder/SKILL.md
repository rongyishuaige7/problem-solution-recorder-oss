---
name: problem-solution-recorder
version: 0.8.9
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

## Command Line Entry

`bin/psr` is the standard entry point. Legacy scripts and a knowledge base's `qs`
keep working and call the same implementation.

```bash
psr configure --global /path/to/kb     # or --project [--dir D]; --show prints root + source
psr init /path/to/kb [--with-examples] # empty knowledge base by default
psr doctor                             # knowledge base + installation/discovery state
psr new "Title" --mode quick|full      # quick uses _templates/快记模板.md
psr finalize <id> --status solved|workaround|unresolved
```

`finalize` validates by target status before writing:

- `solved`: 根因分析, 最终解决方案, 验证方法 must contain real content.
- `workaround`: 最终解决方案, 验证方法, 限制与风险 must contain real content.
- `unresolved`: 原始现象, 后续事项 must contain real content.

It then sets the machine status, syncs `INDEX.md` and the summary index, runs the
secret check, and reports each result. Tool-owned index cells (`草稿`/`draft`/
`待填写`) are updated; human cells such as `已解决（审计）` are kept and reported as a
conflict when they disagree with the machine status. If a later step fails, the
record is already saved and the message includes its id plus the retry command.

## Search And Review

```bash
psr search "MCP timeout" --status solved --limit 5
psr search 'time[o]ut' --regex
psr review --week 2026-W43 [--dry-run]
psr review --open
```

- Search is literal by default; whitespace-separated terms are ANDed. `--regex` treats
  the whole query as one extended regex. Filters: `--status`, `--tool`, `--tag`,
  `--since`, `--until`; `--limit` defaults to 5.
- Results show title, id/date/tools, why it matched, a verification excerpt, and the
  source path. Drafts are marked `[draft]` and labelled as unverified.
- Exit codes: `0` results found, `1` no results, `2` the scan could not run (invalid
  regex, unreadable records).
- `psr review` writes `reviews/<period>.md` with statistics, period records, repeated
  tags/tools, open follow-ups, completed follow-ups (kept out of the todo list), and
  method candidates. Every line carries its source record.
- Generated review content sits between `<!-- PSR:BEGIN REVIEW -->` and
  `<!-- PSR:END REVIEW -->`; text outside the markers (hand-written notes) is preserved,
  and an unchanged run leaves the file byte-identical.
- `psr review --open` lists unfinished `[ ]` items across all records with sources.

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
./scripts/rebuild-index.sh
./scripts/sync-kb-lib.sh
./scripts/perf-check.sh 100
./scripts/print-prompt.sh global-rule
./scripts/doctor-local.sh
./scripts/check-kb.sh
```

`new-record.sh` serializes writes with `<root>/.psr.lock`, so concurrent agents cannot
allocate the same sequence number or lose index rows. It renders the record from the
knowledge base's own `_templates/问题记录模板.md` when present.

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

## Shared Parsing And Locking

One parser and one lock govern every writer:

- `scripts/lib/record-fields.awk` is the only record parser (front matter, inline
  arrays, multi-line lists, fenced code, section caps). It also emits field-level
  warnings for unsupported YAML (block scalars, nested maps) instead of silently
  turning them into empty values.
- `scripts/lib/ids.sh` allocates record ids (three digits, growing past 999).
- `scripts/lib/index.sh` owns INDEX.md schema detection, cell escaping, ordered
  insertion, and row parsing (escape-aware).
- `scripts/lib/lock.sh` implements `<root>/.psr.lock`. Every writer — skill scripts
  and the knowledge base's own CLI — uses the same lock name, so they exclude each
  other. Signals terminate the operation instead of releasing the lock and
  continuing, and a process only removes a lock whose pid file still matches it.
- `scripts/sync-kb-lib.sh` copies both files into `<kb>/bin/lib/`; run
  `sync-kb-lib.sh --check` to detect drift. A knowledge base CLI must load the
  vendored copies rather than embedding its own parser.

## Web Dashboard

A knowledge base may ship a static dashboard under `web/` plus `bin/web-check`.
When present, `doctor-local.sh` runs `bin/web-check`, which regenerates `web/data.js`
in memory (`--check`, no writes), compares content without the generation timestamp,
matches record id/date/status against the canonical parser, and rejects tool/tag values
containing brackets or quotes. The dashboard itself is knowledge-base code;
keep its data generated from Markdown rather than hand-edited.

## Data Integrity

- `new-record.sh` holds `<root>/.psr.lock` (mkdir-based, stale after 300s with a dead pid).
- Record files are written to a temp file and renamed, so a crash cannot leave half a record.
- `INDEX.md` rows are inserted in date order and keep the existing 6- or 7-column schema.
- `rebuild-index.sh` regenerates the human index from record front matter. A 7-column
  index keeps its title/tools/status/关键根因 cells by ID (only date and link are
  refreshed); `--overwrite-handwritten` rebuilds every cell, `--preview` shows a diff,
  and `--check` reports staleness without writing.
- Runs that would not change a file leave it byte-identical (summary index, INDEX.md),
  so repeated maintenance does not create timestamp-only Git diffs.
- `doctor-local.sh` verifies duplicate IDs, broken index links, records missing from the index, status drift, and placeholder conclusions.

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

If the checker flags benign technical text (for example a filename containing `sk-` or a `/cross-session:` slash command), do not delete the context. Add a narrow ERE line to an allowlist file and pass `--allow`:

```bash
./scripts/check-kb.sh "$PROBLEM_SOLUTION_KB_ROOT" --allow .psr-secrets-allow
```

Exit codes are meaningful: `0` clean, `1` potential secrets, `2` the scan could not
complete (unreadable file, invalid allowlist). Treat `2` as "unknown", never as clean.

If write permission is unavailable, output the complete Markdown record and the exact index entries that should be added.
