# AI 入口

If you are an AI agent maintaining this knowledge base, read this file first.

Goal: turn solved problems into reusable records for both humans and future AI agents.

## Key Paths

- Full records: `records/YYYY/`
- Human index: `INDEX.md`
- AI summary index: `AI_SUMMARY_INDEX.md`
- Record template: `_templates/问题记录模板.md`
- Copyable prompts: `AI记录提示词.md`
- Global AI rules: `AI工具记录规则.md`
- Reviews: `reviews/`
- Patterns: `patterns/`

## User Intents

| User says | Action |
| --- | --- |
| "record this" / "记录一下" | Add a record under `records/YYYY/`, update `INDEX.md` and `AI_SUMMARY_INDEX.md` |
| "archive by template" / "按模板归档" | Use `_templates/问题记录模板.md` exactly |
| "summarize recent issues" / "总结最近问题" | Read `AI_SUMMARY_INDEX.md`, then relevant records |
| "daily/weekly review" / "日报/周报" | Update `reviews/` |
| "distill a method" / "沉淀方法" | Add or update `patterns/` |

## New Record Protocol

1. Read `_templates/问题记录模板.md`.
2. Create `records/YYYY/YYYY-MM-DD-NNN-short-topic.md`.
3. Fill the required sections.
4. Update `INDEX.md`.
5. Update `AI_SUMMARY_INDEX.md`.
6. Add or update a pattern if the method is reusable.
7. Redact API keys, tokens, cookies, passwords, private keys, and authorization codes.

## Safety

Never store real secrets. Use `[REDACTED]` for secret values.

## Completion Hook

After a debugging or setup task is complete, ask whether to record it only when it has future value.

Strong signals:

- More than three investigation steps.
- Clear symptom, root cause, and final fix.
- Failed attempts or misleading paths.
- Non-trivial CLI, MCP, API, auth, permission, config, dependency, build, test, or AI-tool behavior.
- The method is likely to be reused.

If at least two signals are present, ask:

```text
这个问题值得记录到问题解决知识库吗？
```

If the user explicitly asked to record, write the record without asking again.
