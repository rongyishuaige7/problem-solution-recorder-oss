# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/rongyishuaige7/problem-solution-recorder-oss/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/rongyishuaige7/problem-solution-recorder-oss/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/rongyishuaige7/problem-solution-recorder-oss/releases/tag/v0.1.0
