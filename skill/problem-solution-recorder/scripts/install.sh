#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$( ( unset CDPATH; cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P ) )"
SKILL_DIR="$( ( unset CDPATH; cd -P -- "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd -P ) )"
SKILL_NAME="$(basename "$SKILL_DIR")"
VALIDATE="$SCRIPT_DIR/validate-skill.sh"

MODE="copy"
TARGETS=()
ACTION="install"
DRY_RUN=0
SKIP_VALIDATE=0

usage() {
  cat <<'EOF'
Install or uninstall problem-solution-recorder into local AI skill directories.

Usage:
  install.sh [--copy|--symlink] [--codex] [--claude] [--cursor] [--agents] [--openclaw] [--all]
  install.sh --uninstall [--codex] ... [--all]
  install.sh [--dry-run] [--skip-validate]

Default install:
  --copy --all

Targets:
  codex    ~/.codex/skills/problem-solution-recorder
  claude   ~/.claude/skills/problem-solution-recorder
  cursor   ~/.cursor/skills-cursor/problem-solution-recorder
  agents   ~/.agents/skills/problem-solution-recorder
  openclaw ~/.openclaw/skills/problem-solution-recorder

Safety:
  --uninstall removes a target only if it is a symlink pointing at this skill directory,
  or a copy directory that contains .psr-installed-from matching this skill directory.
  Other directories are never deleted.

Install runs validate-skill.sh first unless --skip-validate is passed.
EOF
}

add_target() {
  TARGETS+=("$1")
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --copy) MODE="copy" ;;
    --symlink) MODE="symlink" ;;
    --codex) add_target "codex" ;;
    --claude) add_target "claude" ;;
    --cursor) add_target "cursor" ;;
    --agents) add_target "agents" ;;
    --openclaw) add_target "openclaw" ;;
    --all) TARGETS=("codex" "claude" "cursor" "agents" "openclaw") ;;
    --uninstall) ACTION="uninstall" ;;
    --dry-run) DRY_RUN=1 ;;
    --skip-validate) SKIP_VALIDATE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [[ "${#TARGETS[@]}" -eq 0 ]]; then
  TARGETS=("codex" "claude" "cursor" "agents" "openclaw")
fi

target_dir_for() {
  case "$1" in
    codex) printf '%s\n' "$HOME/.codex/skills/$SKILL_NAME" ;;
    claude) printf '%s\n' "$HOME/.claude/skills/$SKILL_NAME" ;;
    cursor) printf '%s\n' "$HOME/.cursor/skills-cursor/$SKILL_NAME" ;;
    agents) printf '%s\n' "$HOME/.agents/skills/$SKILL_NAME" ;;
    openclaw) printf '%s\n' "$HOME/.openclaw/skills/$SKILL_NAME" ;;
    *) return 1 ;;
  esac
}

canonical_dir() {
  ( unset CDPATH; cd -P -- "$1" >/dev/null 2>&1 && pwd -P )
}

skill_canonical="$(canonical_dir "$SKILL_DIR")"

if [[ "$ACTION" == "install" && "$SKIP_VALIDATE" -eq 0 ]]; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[dry-run] would run: %s\n' "$VALIDATE"
  else
    "$VALIDATE" --quiet
  fi
fi

copy_skill() {
  local target="$1"
  mkdir -p "$target"
  cp -R "$SKILL_DIR/." "$target/"
  printf '%s\n' "$skill_canonical" > "$target/.psr-installed-from"
}

install_one() {
  local target_name="$1"
  local target
  target="$(target_dir_for "$target_name")"
  mkdir -p "$(dirname "$target")"

  if [[ -L "$target" ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      printf '[dry-run] would remove existing symlink: %s\n' "$target"
    else
      rm "$target"
    fi
  elif [[ -e "$target" ]]; then
    printf '[skip] %s exists and is not a symlink; move it manually if you want to replace it\n' "$target"
    return 0
  fi

  if [[ "$MODE" == "symlink" ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      printf '[dry-run] would symlink %s -> %s\n' "$target" "$SKILL_DIR"
    else
      ln -s "$SKILL_DIR" "$target"
      printf '[link] %s -> %s\n' "$target" "$SKILL_DIR"
    fi
  else
    if [[ "$DRY_RUN" -eq 1 ]]; then
      printf '[dry-run] would copy skill to %s\n' "$target"
    else
      copy_skill "$target"
      printf '[copy] %s -> %s\n' "$SKILL_DIR" "$target"
    fi
  fi
}

uninstall_one() {
  local target_name="$1"
  local target
  target="$(target_dir_for "$target_name")"

  if [[ ! -e "$target" && ! -L "$target" ]]; then
    printf '[skip] not installed: %s\n' "$target"
    return 0
  fi

  if [[ -L "$target" ]]; then
    local resolved_canonical=""
    resolved_canonical="$(readlink -f "$target" 2>/dev/null || true)"
    if [[ "$resolved_canonical" == "$skill_canonical" ]]; then
      if [[ "$DRY_RUN" -eq 1 ]]; then
        printf '[dry-run] would remove symlink %s\n' "$target"
      else
        rm "$target"
        printf '[removed] symlink %s\n' "$target"
      fi
    else
      local link_dest
      link_dest="$(readlink "$target" 2>/dev/null || true)"
      printf '[skip] symlink does not point at this skill: %s -> %s\n' "$target" "${link_dest:-?}"
    fi
    return 0
  fi

  if [[ -d "$target" ]]; then
    local marker="$target/.psr-installed-from"
    if [[ -f "$marker" ]]; then
      local stored
      stored="$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$marker" | sed -n '1p')"
      local stored_canonical=""
      if [[ -n "$stored" && -d "$stored" ]]; then
        stored_canonical="$(canonical_dir "$stored" 2>/dev/null || true)"
      fi
      if [[ "$stored_canonical" == "$skill_canonical" ]]; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
          printf '[dry-run] would remove directory %s\n' "$target"
        else
          rm -rf "$target"
          printf '[removed] directory %s\n' "$target"
        fi
      else
        printf '[skip] directory marker does not match this skill: %s\n' "$target"
      fi
    else
      printf '[skip] directory missing .psr-installed-from (not installed by this script): %s\n' "$target"
    fi
    return 0
  fi

  printf '[skip] unexpected install target type: %s\n' "$target"
}

if [[ "$ACTION" == "uninstall" ]]; then
  for target in "${TARGETS[@]}"; do
    uninstall_one "$target"
  done
else
  for target in "${TARGETS[@]}"; do
    install_one "$target"
  done
fi
