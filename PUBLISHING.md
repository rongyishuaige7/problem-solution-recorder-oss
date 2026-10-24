# Publishing runbook

Checklist for shipping **Problem Solution Recorder** to GitHub and local installs. ClawdHub is not used.

## Pre-flight

- [ ] `skill/problem-solution-recorder/scripts/validate-skill.sh` passes.
- [ ] `skill/problem-solution-recorder/scripts/smoke-test.sh` passes.
- [ ] `skill/problem-solution-recorder/scripts/check-kb.sh examples/minimal-knowledge-base` passes.
- [ ] `CHANGELOG.md` updated (Keep a Changelog).
- [ ] `skill/problem-solution-recorder/SKILL.md` frontmatter `version:` bumped for a new registry publish.
- [ ] `metadata.openclaw.homepage` in `SKILL.md` points at the canonical GitHub URL.
- [ ] `examples/minimal-knowledge-base/` mirrors `assets/minimal-knowledge-base/` if templates changed.

## GitHub

1. Create the repository (example — **confirm org/user and do not push secrets**):

   ```bash
   gh repo create rongyishuaige7/problem-solution-recorder-oss --public --source=. --remote=origin
   git push -u origin main
   git push origin v0.8.14
   ```

   If you prefer a manual remote:

   ```bash
   git remote add origin git@github.com:rongyishuaige7/problem-solution-recorder-oss.git
   git push -u origin main
   ```

   Confirm `.gitignore` covers local env files before the first push.

2. Tag releases:

   ```bash
   git tag -a v0.8.14 -m "v0.8.14"
   git push origin v0.8.14
   ```

3. Add GitHub **Topics** (suggested): `agent-skills`, `markdown`, `knowledge-base`, `debugging`, `mcp`, `codex`, `claude`, `cursor`, `openclaw`, `devtools`.

## ClawdHub (OpenClaw registry) — not planned

This project does not publish to ClawdHub. The skill is distributed by cloning the
repository and installing locally (`install.sh --symlink` or `--copy`). Keep the
`metadata.openclaw` block in `SKILL.md` for OpenClaw users who install the folder
manually, but do not run `clawhub publish`.

## Post-publish verification

- [ ] Fresh clone smoke test:

  ```bash
  git clone https://github.com/rongyishuaige7/problem-solution-recorder-oss.git
  cd problem-solution-recorder-oss
  skill/problem-solution-recorder/scripts/smoke-test.sh
  ```

- [ ] Optional local install from the clone:

  ```bash
  skill/problem-solution-recorder/scripts/install.sh --dry-run --symlink --codex
  skill/problem-solution-recorder/scripts/install.sh --symlink --codex
  ```

## Other communities

When posting to forums or newsletters, link to:

- GitHub repository root for documentation and issues.
- `skill/problem-solution-recorder/` subtree for skill-only consumers.

Include one-line positioning: *Markdown-native incident archive with dual indexes and optional patterns/reviews.*
