# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/rongyishuaige7/problem-solution-recorder-oss/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/rongyishuaige7/problem-solution-recorder-oss/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/rongyishuaige7/problem-solution-recorder-oss/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/rongyishuaige7/problem-solution-recorder-oss/releases/tag/v0.1.0
