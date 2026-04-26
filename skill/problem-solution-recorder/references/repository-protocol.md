# Problem-Solution Repository Protocol

This reference gives the generic operating protocol for a problem-solution knowledge base. The live repository is the source of truth; this skill only tells an agent how to use it.

## Root Resolution

Resolve the repository root in this order:

1. Environment variable: `PROBLEM_SOLUTION_KB_ROOT`
2. Project marker file: `.problem-solution-root`
3. User config file: `$XDG_CONFIG_HOME/problem-solution-recorder/root`
4. User config fallback: `~/.config/problem-solution-recorder/root`
5. Ask the user for a path, or initialize a new repository from the bundled template.

The root should contain an `AI入口.md` file. If it does not, either the wrong path was selected or the repository has not been initialized.

## Repository Roles

- `records/YYYY/*.md`: full incident records for specific solved problems.
- `INDEX.md`: human-readable table of records.
- `AI_SUMMARY_INDEX.md`: compact AI index for recall, clustering, and summaries.
- `_templates/问题记录模板.md`: canonical full record template.
- `_templates/快记模板.md`: quick capture template.
- `_templates/方法论模板.md`: reusable pattern template.
- `_templates/日报复盘模板.md`: daily review template.
- `_templates/周报复盘模板.md`: weekly review template.
- `patterns/*.md`: reusable methods distilled from one or more records.
- `reviews/*.md`: daily, weekly, and monthly review files.
- `AI入口.md`: canonical AI entry point and current protocol.
- `AI记录提示词.md`: copyable prompts for other tools.
- `AI工具记录规则.md`: global rule snippets for AI tools.

The skill bundles helper scripts for initialization, diagnosis, record skeletons, AI index regeneration, and prompt printing. A knowledge base may also provide its own CLI; if it does, prefer the repository-native CLI when it is more capable.

## Trigger Policy

Record proactively only when the solved issue has future value.

Strong signals:

- More than three investigation steps.
- Clear original symptom and final root cause.
- At least one failed attempt or misleading path.
- Tooling or environment complexity: CLI, MCP, API, proxy, auth, permissions, local config, system dependency, build/test error, adapter, browser automation, or AI tool behavior.
- The final solution is likely to be reused.
- The user spent visible time diagnosing the problem.

Weak signals:

- Ordinary conceptual Q&A.
- Tiny edit with no troubleshooting value.
- No verified final solution.
- User explicitly says not to record.

If the user did not ask to record but the issue is worth keeping, ask briefly before writing:

```text
This issue is worth recording. Should I archive it in your problem-solution knowledge base?
```

Use the user's language when asking.

If the user explicitly asks to record, do not ask again.

## New Full Record Checklist

1. Read `AI入口.md`.
2. Read `_templates/问题记录模板.md`.
3. Identify the solved date and target year.
4. Create `records/YYYY/YYYY-MM-DD-NNN-short-topic.md`.
5. Preserve concrete evidence:
   - user-visible symptom
   - exact command or tool call when useful
   - key error output
   - relevant file/config paths
   - failed attempts
   - root cause
   - final fix
   - verification
   - reusable lesson
6. Update `INDEX.md`.
7. Update `AI_SUMMARY_INDEX.md` or run `bin/qs ai-index`.
8. Add or update `patterns/` when a reusable method emerges.
9. Run or emulate `bin/qs check` before final response.
10. Tell the user which files changed and whether any verification was skipped.

## Required Full Record Sections

Use the headings from the repository template exactly:

- `一句话结论`
- `原始现象`
- `环境与关键配置`
- `排查时间线`
- `失败尝试`
- `根因分析`
- `最终解决方案`
- `验证方法`
- `复用经验`
- `后续事项`

Prefer factual, concrete entries over polished narrative. Distinguish guesses from verified facts.

## AI Summary Index Fields

Each `AI_SUMMARY_INDEX.md` entry should be compact but useful for future recall:

- `source`
- `date`
- `status`
- `tools`
- `tags`
- `problem_signature`
- `root_cause`
- `final_fix`
- `verification`
- `reusable_lesson`
- `follow_up`

The index should let a future agent decide whether to open the full record.

## Records vs Patterns

Use `records/` for a concrete incident:

- what happened
- what the user saw
- what was tried
- what caused it
- what fixed it
- how it was verified

Use `patterns/` for reusable methods:

- MCP debugging checklist
- API key and environment variable diagnosis
- tool adapter timeout triage
- Ubuntu permission/system dependency troubleshooting
- AI tool search fallback strategy
- build and dependency recovery playbooks

A pattern can come from one or multiple records.

## Review Workflow

When the user asks for a daily, weekly, or monthly review:

1. Read `AI_SUMMARY_INDEX.md`.
2. Read matching records only when the index is insufficient.
3. Update:
   - `reviews/YYYY-MM-DD.md` for daily review
   - `reviews/YYYY-Www.md` for weekly review
   - `reviews/YYYY-MM.md` for monthly review
4. Include repeated problems, reusable lessons, unresolved follow-ups, and next actions.

## Completion Hook Protocol

This is a portable agent-facing hook. It does not require a background daemon.

After a debugging or setup task is complete, silently check whether the issue has future value. If at least two strong signals are present, and the user did not explicitly opt out, ask one short question:

```text
这个问题值得记录到问题解决知识库吗？
```

If the user explicitly asked to record, skip the question and write the record.

This rule is intentionally conservative. The agent should not interrupt for ordinary Q&A, tiny edits, or unfinished investigations.

## Search Workflow

Search order:

1. `AI_SUMMARY_INDEX.md`
2. `patterns/`
3. relevant `records/YYYY/*.md`
4. `reviews/` only if the question is about trends or recaps

Use `rg` when available. If the repository has `bin/qs`, prefer its search command when it adds useful formatting.

## Secret Handling

Never write real values for:

- API keys
- tokens
- cookies
- passwords
- private keys
- authorization codes
- session IDs that grant access
- bearer tokens

Use `[REDACTED]` for secret values.

Safe:

```text
EXAMPLE_API_KEY=[REDACTED]
```

Unsafe:

```text
EXAMPLE_API_KEY=[DO_NOT_COMMIT_SECRET_VALUE]
```

If a checker flags false positives, explain them rather than deleting useful technical context.

## Failure Mode

If the agent cannot write files:

1. Produce the full record Markdown.
2. Produce the `INDEX.md` row to add.
3. Produce the `AI_SUMMARY_INDEX.md` entry to add.
4. Mention that the repository was not modified.

Do not silently skip indexing.
