# Contributing

Thanks for helping improve Problem Solution Recorder.

## Development setup

1. Clone the repository.
2. Work primarily under `skill/problem-solution-recorder/` when changing the publishable skill.
3. Keep `examples/minimal-knowledge-base/` in sync with `skill/problem-solution-recorder/assets/minimal-knowledge-base/` when you change the bundled template (see below).

## Checks to run locally

```bash
skill/problem-solution-recorder/scripts/validate-skill.sh
skill/problem-solution-recorder/scripts/smoke-test.sh
```

If `shellcheck` is installed:

```bash
shellcheck -x skill/problem-solution-recorder/scripts/*.sh
```

## Syncing the example mirror

After editing files under `skill/problem-solution-recorder/assets/minimal-knowledge-base/`, refresh the GitHub-visible example:

```bash
cp -a skill/problem-solution-recorder/assets/minimal-knowledge-base/. examples/minimal-knowledge-base/
# restore example-only files if needed:
printf '/absolute/path/to/problem-solution-kb\n' > examples/minimal-knowledge-base/.problem-solution-root.example
```

Then re-apply any intentional overrides under `examples/minimal-knowledge-base/README.md`.

## Versioning and changelog

- Follow [Semantic Versioning](https://semver.org/).
- Bump `version:` in `skill/problem-solution-recorder/SKILL.md` for every registry publish (ClawdHub rejects duplicate versions).
- Update `CHANGELOG.md` using [Keep a Changelog](https://keepachangelog.com/) conventions.
- Add an `[Unreleased]` section for work in progress.

## Pull requests

- Prefer small, focused PRs.
- Describe motivation, user-visible changes, and any platform-specific notes (Codex / Claude / Cursor / OpenClaw).
- Ensure `validate-skill.sh` and `smoke-test.sh` pass.

## Security

Do not commit real secrets. Use `[REDACTED]` placeholders in examples.
