# Publishing runbook

Checklist for shipping **Problem Solution Recorder** to GitHub, ClawdHub, and local installs.

## Pre-flight

- [ ] `skill/problem-solution-recorder/scripts/validate-skill.sh` passes.
- [ ] `skill/problem-solution-recorder/scripts/smoke-test.sh` passes.
- [ ] `CHANGELOG.md` updated (Keep a Changelog).
- [ ] `skill/problem-solution-recorder/SKILL.md` frontmatter `version:` bumped for a new registry publish.
- [ ] `metadata.openclaw.homepage` in `SKILL.md` points at the canonical GitHub URL.
- [ ] `examples/minimal-knowledge-base/` mirrors `assets/minimal-knowledge-base/` if templates changed.

## GitHub

1. Create the repository (example — **confirm org/user and do not push secrets**):

   ```bash
   gh repo create rongyi/problem-solution-recorder-oss --public --source=. --remote=origin
   git push -u origin main
   git push origin v0.1.0
   ```

   If you prefer a manual remote:

   ```bash
   git remote add origin git@github.com:rongyi/problem-solution-recorder-oss.git
   git push -u origin main
   ```

   Confirm `.gitignore` covers local env files before the first push.

2. Tag releases:

   ```bash
   git tag -a v0.1.0 -m "v0.1.0"
   git push origin v0.1.0
   ```

3. Add GitHub **Topics** (suggested): `agent-skills`, `markdown`, `knowledge-base`, `debugging`, `mcp`, `codex`, `claude`, `cursor`, `openclaw`, `devtools`.

## ClawdHub (OpenClaw registry)

1. Install and log in to the **ClawHub** CLI (`clawhub`).
2. Accept license terms on [clawhub.ai](https://clawhub.ai) if the CLI instructs you to.
3. Publish **only** the skill directory:

   ```bash
   clawhub publish ./skill/problem-solution-recorder \
     --slug problem-solution-recorder \
     --name "Problem Solution Recorder" \
     --version 0.1.0 \
     --tags "knowledge-base,debugging,markdown,agents" \
     --changelog "See CHANGELOG.md for 0.1.0"
   ```

4. Notes:
   - Duplicate `version` values are rejected — always bump `SKILL.md` for a new publish.
   - Registry bundles are size-limited (on the order of tens of MB); keep binaries and large assets out of the skill folder.
   - If your CLI documents `--accept-license` (or similar), use it in CI/non-interactive environments.

## Post-publish verification

- [ ] ClawdHub listing shows the new version and readable description.
- [ ] Fresh clone smoke test:

  ```bash
  git clone https://github.com/rongyi/problem-solution-recorder-oss.git
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
- `skill/problem-solution-recorder/` subtree (or ClawdHub page) for skill-only consumers.

Include one-line positioning: *Markdown-native incident archive with dual indexes and optional patterns/reviews.*
