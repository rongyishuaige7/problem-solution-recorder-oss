# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/rongyishuaige7/problem-solution-recorder-oss/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/rongyishuaige7/problem-solution-recorder-oss/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/rongyishuaige7/problem-solution-recorder-oss/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/rongyishuaige7/problem-solution-recorder-oss/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/rongyishuaige7/problem-solution-recorder-oss/releases/tag/v0.1.0
