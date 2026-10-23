# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.8.2] - 2026-10-23

### Fixed

- Review marker handling now uses whole-line matches everywhere: a file whose markers
  sit on the same line, appear inline in prose, repeat, or are reversed is refused with
  the counts and line numbers; only a valid pair (one each, BEGIN strictly before END)
  is refreshed, and a file without any marker text is migrated with a backup.
- A crashed reclaimer's `<lock>.reclaim` no longer blocks writers forever: the marker
  records its owner, and a dead owner or a marker older than 60s is cleaned before the
  stale lock is reclaimed.
- `finalize` locates, validates and writes inside the same write lock, so content that
  becomes empty while waiting is rejected instead of archived; `--dry-run` stays
  read-only.
- Section validation understands multi-line HTML comments and both ``` and ~~~ fences;
  a comment-only block no longer counts as content, while real commands and output do.
- An index row inserted by `finalize` uses the record's date, tools and tags; `doctor`
  now also reports INDEX/record date mismatches.
- `rebuild-index.sh --allow-empty` (and `psr index --rebuild --allow-empty`) rebuilds an
  empty index; without the flag, dropping existing rows is refused with a hint.
- The record parser keeps fenced content as evidence (a `##` inside a fence still never
  starts a section), so verification blocks appear in the summary and the web data.
- `psr search` no longer byte-truncates the verification excerpt under `LC_ALL=C`.

### Changed

- Web data is record-authoritative: an existing-but-empty section or `tags: []` stays
  empty instead of falling back to a stale summary entry; `search_text` and separate
  conclusion/signature fields keep CLI and page search scopes aligned.
- `bin/web-check` compares tags and body-field presence against the canonical parser, so
  a generator that silently falls back to stale summary content is reported instead of
  self-certifying.
- The dashboard shows which fields matched on each card when a query is active.
- Narrow layouts no longer inherit a 505px minimum width: the shell/content grids use
  `minmax(0, 1fr)` and long tokens wrap, so a 390px viewport renders at 390px.
- A knowledge base's `qs new` reports Web sync failures as partial success (exit 2) and
  no longer prints “已同步” when generation failed.


## [0.8.1] - 2026-10-22

### Fixed

- Reclaiming a stale write lock is now mutual-exclusive: the reclaimer takes
  `<lock>.reclaim` and re-checks the stale instance before deleting, so two reclaimers
  can no longer delete each other's fresh lock and enter the critical section together.
- Record enumeration failures (unreadable directory, `find` error) abort the summary,
  index rebuild, doctor and `psr` reads instead of looking like an empty knowledge base;
  derived files are left unchanged.
- `psr review` takes the shared write lock, refuses files whose PSR markers are missing,
  duplicated or reversed, and migrates pre-marker hand-written reviews to a timestamped
  backup while preserving their content.
- `finalize` rejects records that are still the unedited template and ignores HTML
  comments, label-only lines, placeholder prose and comment-only fences when checking
  section content.
- `finalize` writes `status` only inside the front matter (inserting it when missing),
  preserves six-column `Tags`, and reports record / INDEX / summary / Web / secret check
  separately with exact paths.
- A failed secret scan no longer reports success: findings exit 1, an unknown scan
  result exits 2, both with masked locations and a recovery command.
- Record IDs are handled end to end: four-digit sequences are printed in full, a year or
  any prefix is rejected, and duplicate IDs are refused with the candidate paths.
- `psr new` reports the saved path and ID even when the summary refresh fails (exit 3).
- Search passes the query through the environment, so literal backslashes match
  (Windows paths, escaped logs); long Chinese review text is no longer byte-truncated.
- `doctor` accepts quoted dates, maps Chinese index labels before comparing status, and
  de-duplicates IDs with the correct field separator.
- Web data prefers record bodies over the summary index, parses sections with fence
  awareness, keeps fenced evidence, accepts both summary formats, and compares generated
  content without the timestamp so an unchanged run keeps the file byte-identical.
- A knowledge base's `qs` now calls the shared summary script, so `psr` and `qs` produce
  the same AI index; `psr index [--rebuild] [--web]` refreshes derived files on demand.
- Web: the selection is resolved before rendering (first card is active), keyboard focus
  survives Enter and tag toggles, invalid or reversed date filters are cleared, mobile
  gets a “返回结果” action that restores the scroll position, and filters collapse by
  default on narrow screens.
- README quick start shows the `psr` path; stale claims about vendoring `psr` and about
  doctor regenerating web data were corrected.


## [0.8.0] - 2026-10-22

### Added

- `doctor-local.sh` reports records whose front matter lacks a `date` field, and runs
  `bin/web-check` when a knowledge base ships one.

### Changed

- Knowledge base dashboard (in the KB repository, not this skill): URL-persisted search,
  filters and selection; status filter covers draft/investigating; date-range filter;
  zero-result state clears the detail pane and offers a reset button; generated time is a
  real timestamp shown separately from record dates; all dynamic text is rendered with
  DOM text nodes; keyboard selection (Up/Down/Enter/Space/Escape) and mobile detail
  scrolling.
- `bin/web-check` keeps `web/data.js` consistent with the canonical parser and rejects
  tool/tag values containing brackets or quotes.

### Fixed

- One record used a `日期:` front-matter key instead of `date:`, which made the dashboard
  and the canonical parser disagree; the record was repaired and the doctor now checks
  for it.


## [0.7.0] - 2026-10-22

### Added

- `psr search`: literal (default) or `--regex` search over title, id, problem signature,
  root cause, fix, verification, lessons, tags, tools, and follow-ups. Whitespace-separated
  terms are ANDed; results are scored by field and recency, capped by `--limit` (default 5).
  Filters: `--status`, `--tool`, `--tag`, `--since`, `--until`. Drafts are marked and
  labelled unverified. Exit codes distinguish no results (1) from a failed scan (2).
- `psr review`: weekly/monthly/daily retrospectives with statistics, period records,
  repeated tags/tools, open and completed follow-ups (kept separate), and method
  candidates; every line carries its source. Generated content is marker-scoped, so
  hand-written notes survive and unchanged runs are byte-identical.
- `psr review --open`: unfinished follow-ups across all records with sources.
- `record-fields.awk` also emits `follow_items`, preserving `[ ]`/`[x]` state per item.


## [0.6.0] - 2026-10-22

### Added

- `bin/psr`: unified CLI with `configure`, `init`, `doctor`, `new`, and `finalize`.
  `configure --show` reports the resolved knowledge base and where the setting came
  from (env, project marker, XDG config). `new --mode quick` uses the quick template.
- `finalize <id> --status ...` validates per target status (solved / workaround /
  unresolved), sets the machine status, syncs both indexes, runs the secret check,
  and reports each result. Failures after the record is written include the record
  id and the retry command.
- Status vocabulary in `lib/index.sh`: tool-owned cells are updated, human cells such
  as `已解决（审计）` are preserved and reported when they disagree with the machine status.
- `init-kb.sh` creates an empty knowledge base by default; `--with-examples` keeps the
  sample record/pattern/review.
- `install.sh --bin [--bin-dir DIR]` links `psr` into `~/.local/bin` and refuses to
  replace an unrelated existing command.
- `sync-kb-lib.sh` copies the shared record libraries into a knowledge base so its own
  CLI uses the same parser, id, lock and index rules. `psr` itself stays in the skill.

### Changed

- Draft partition in the summary index is driven by status only; an archived record
  with a missing conclusion stays visible (doctor still reports the placeholder).
- `install.sh --bin` only links the command; it no longer installs the skill into every
  tool directory as a side effect.

### Fixed

- `bin/psr` follows symlinks, so a `~/.local/bin/psr` link still finds its skill
  directory and configuration.


## [0.5.1] - 2026-10-22

### Added

- `scripts/lib/ids.sh` (sequence allocation), `scripts/lib/index.sh` (schema detection,
  escaping, ordered insertion, escape-aware row parsing), and `scripts/lib/secrets.sh`
  (pattern, benign-value rules, masking). `new-record.sh`, `rebuild-index.sh`,
  `check-kb.sh`, and `sync-kb-lib.sh` use them.
- `rebuild-index.sh --preview` (diff) and `--overwrite-handwritten`; a 7-column index now
  keeps its title/tools/status/关键根因 cells by ID, so rebuilding a real knowledge base
  is non-destructive.
- Field-level YAML diagnostics: block scalars and nested maps are reported per record
  and field instead of silently becoming empty values.
- `perf-check.sh`: 100-record cold/warm timings and byte-identical check.

### Changed

- Summary index and INDEX.md writes are skipped when the result is byte-identical, so
  repeated maintenance no longer produces timestamp-only diffs.
- `rebuild-index.sh` escapes cells in pure bash; 100 records: ~10.7s → under 0.5s.

### Fixed

- A 7-column rebuild used to rewrite every row (statuses and tool names changed case);
  it now preserves the human-authored cells and only refreshes date and link.


## [0.5.0] - 2026-10-22

### Added

- `scripts/lib/record-fields.awk`: the single record parser (front matter, inline
  arrays, multi-line lists, fenced code, section caps) used by the summary index,
  `rebuild-index.sh`, and `doctor-local.sh`.
- `scripts/lib/lock.sh` plus `sync-kb-lib.sh`: one lock (`<root>/.psr.lock`) and one
  parser shared with a knowledge base's own CLI; `--check` reports vendored drift.

### Changed

- Lock protocol unified: `new-record.sh`, `update-ai-summary-index.sh`, and
  `rebuild-index.sh` take the same lock, and `bin/qs` uses the same file, so no two
  writers can touch one knowledge base at once.
- Signal handling terminates the operation (`exit 130`) instead of releasing the
  lock and continuing; release only removes a lock whose pid file matches this
  process.
- `check-kb.sh` and `qs check` share value-level exception rules and masking.

### Fixed

- ShellCheck SC2016 in `update-ai-summary-index.sh` (Markdown backticks inside
  single-quoted printf formats) broke the Ubuntu CI job before validation ran.
- Summary/rebuild reported success after an unreadable record because failures in
  the process substitution never reached the main script; parsing now runs into a
  temp file and the index is left untouched on any read error or short record count.
- `doctor-local.sh` truncated IDs to three digits (1000/1001 looked duplicated),
  skipped link checks when `records/` was empty, and mis-parsed rows whose title
  contained an escaped `|`, hiding real status drift.
- `qs check` still filtered whole lines: `[REDACTED]` on the same line suppressed a
  real key, grep errors were swallowed, and values were printed unmasked.
- `web/generate-data.js` kept its own front-matter parser, so `tools: ["codex", "mcp"]`
  produced `["codex"` / `"mcp"]` filter entries; inline arrays are now normalized.
- Lock mtime detection called `stat -f %m` first. GNU `stat -f` means "filesystem
  status": it prints the filesystem block to stdout and exits 1, so the BSD fallback
  was concatenated with that output and any contended lock hit an arithmetic error
  (concurrent writers died instantly, leaving one record). The helper now tries GNU
  `-c %Y`, falls back to BSD `-f %m`, rejects non-numeric output, and never treats an
  unknown mtime as "stale".


## [0.4.0] - 2026-10-22

### Added

- `new-record.sh` takes a knowledge base write lock (`<root>/.psr.lock`), writes records
  through a temp file + rename, and renders the skeleton from
  `_templates/问题记录模板.md` (override with `--template`, skip locking with `--no-lock`).
- `rebuild-index.sh`: regenerate `INDEX.md` from record front matter, preserving the
  6- or 7-column schema and any content outside the table; `--check` and `--dry-run`.
- `doctor-local.sh` consistency checks: duplicate IDs, broken index links, records missing
  from the index, status drift between index and front matter, placeholder conclusions.
- `init-kb.sh --dry-run`, and `--force` now lists and backs up every file it would overwrite.
- `install.sh --upgrade` and `--dir <path>`; `--dry-run` no longer creates directories.

### Changed

- `update-ai-summary-index.sh` parses each record in a single awk pass, supports multi-line
  YAML lists and inline arrays, skips fenced code blocks, caps field length, and moves
  unfilled drafts into a separate "Drafts" section. 100 records: ~10.5s → under 1s.
- `check-kb.sh` judges exceptions on the matched value only (not the path or the whole line),
  masks reported values, validates allowlist patterns up front, and returns `2` when the
  scan could not complete instead of reporting a clean result.
- `resolve-kb-root.sh` resolves relative `.problem-solution-root` values against the marker's
  directory and normalizes the resolved path.

### Fixed

- `init-kb.sh` could overwrite a non-empty directory without `--force`: `find ... | read`
  under `pipefail` made the emptiness check unreliable.
- Sequence numbers stopped at three digits, so the 1000th record of a day reused an existing
  ID and overwrote the file.
- `update-ai-summary-index.sh` lost hand-written content when the generated markers were
  reversed or duplicated; it now validates count and order and leaves the file untouched.
- `new-record.sh` placed backfilled (older) dates at the top of the index instead of the bottom.
- `awk -v` unescaped `\|` in index rows, producing wrong column counts for titles with pipes.
- Concurrent runs shared fixed temp file names and could lose index rows.


## [0.3.0] - 2026-10-22

### Added

- `new-record.sh` detects the existing `INDEX.md` header and writes a matching row, including 7-column `ID | 日期 | 标题 | 工具/系统 | 状态 | 关键根因 | 记录` tables; creates `INDEX.md` when missing.
- Index rows are inserted in date-descending order instead of being appended after unrelated sections.
- `check-kb.sh --allow <file>` allowlist support, plus a hint line when a scan fails.
- Richer record template (背景, 影响范围, 修改的文件, AI 摘要提示, layered root cause) and a matching skeleton in `new-record.sh`; `draft` added to the status enum.
- macOS CI job (`validate-macos`) running validate, example scan, and smoke test.
- Smoke test regressions: 7-column index insertion, skeleton sections, manual-note preservation, secret-scanner true/false positives.

### Changed

- `doctor-local.sh` treats daily/weekly review templates as optional (`[warn]`) instead of hard failures.
- `PUBLISHING.md` drops the ClawdHub publish flow; local install is the supported path.

### Fixed

- Rows containing `|` lost their Markdown escape because `awk -v` interprets `\|`; row content now travels through the environment.
- Secret scanner false positives on `task-...` filenames (`sk-` rule), `/cross-session:` slash commands, and local `session_id` values.
- `validate-skill.sh` no longer writes fixed paths under `/tmp` (concurrent runs clobbered each other).
- `install.sh --uninstall` no longer depends on GNU `readlink -f`.
- `update-ai-summary-index.sh` renders inline YAML arrays (`["codex", "mcp"]`) as plain `codex, mcp` lists.


## [0.2.0] - 2026-07-14

### Fixed

- Shell scripts: satisfy ShellCheck (SC1007, SC2154, SC2016); CI `actions/checkout@v6`.
- Preserve manual notes in `AI_SUMMARY_INDEX.md` while refreshing generated entries.
- Escape Markdown table cells when adding new records to `INDEX.md`.

### Added

- `check-kb.sh` scans Markdown knowledge bases for likely leaked secrets.
- CI now scans the example knowledge base for likely leaked secrets.

## [0.1.0] - 2026-04-26

### Added

- Initial public skill `problem-solution-recorder` with `SKILL.md`, references, and helper scripts.
- Configurable knowledge base root resolution (`PROBLEM_SOLUTION_KB_ROOT`, `.problem-solution-root`, XDG config).
- Bundled minimal Markdown knowledge base template with sample record, pattern, and review.
- Local installer for Codex, Claude, Cursor, Agents, and OpenClaw skill directories (`install.sh`).
- `validate-skill.sh`, `smoke-test.sh`, `doctor-local.sh`, and prompt/record utilities.
- `agents/*.yaml` metadata for multiple runtimes.
- GitHub Actions workflow for validation and smoke tests.

[Unreleased]: https://github.com/rongyishuaige7/problem-solution-recorder-oss/compare/v0.8.2...HEAD
[0.8.2]: https://github.com/rongyishuaige7/problem-solution-recorder-oss/compare/v0.8.1...v0.8.2
[0.8.1]: https://github.com/rongyishuaige7/problem-solution-recorder-oss/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/rongyishuaige7/problem-solution-recorder-oss/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/rongyishuaige7/problem-solution-recorder-oss/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/rongyishuaige7/problem-solution-recorder-oss/compare/v0.5.1...v0.6.0
[0.5.1]: https://github.com/rongyishuaige7/problem-solution-recorder-oss/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/rongyishuaige7/problem-solution-recorder-oss/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/rongyishuaige7/problem-solution-recorder-oss/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/rongyishuaige7/problem-solution-recorder-oss/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/rongyishuaige7/problem-solution-recorder-oss/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/rongyishuaige7/problem-solution-recorder-oss/releases/tag/v0.1.0
