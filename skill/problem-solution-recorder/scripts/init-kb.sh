#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$( ( unset CDPATH; cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P ) )"
SKILL_DIR="$( ( unset CDPATH; cd -P -- "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd -P ) )"
TEMPLATE_DIR="$SKILL_DIR/assets/minimal-knowledge-base"

usage() {
  cat <<'EOF'
Initialize a problem-solution knowledge base from the bundled template.

Usage:
  init-kb.sh /path/to/problem-solution-kb [--force]

The target directory must be empty unless --force is used.
EOF
}

target="${1:-}"
force="${2:-}"

if [[ "$target" == "-h" || "$target" == "--help" || -z "$target" ]]; then
  usage
  [[ -n "$target" ]] && exit 0 || exit 2
fi

if [[ "$force" != "" && "$force" != "--force" ]]; then
  printf 'Unknown option: %s\n' "$force" >&2
  usage >&2
  exit 2
fi

[[ -d "$TEMPLATE_DIR" ]] || {
  printf 'Template directory not found: %s\n' "$TEMPLATE_DIR" >&2
  exit 1
}

mkdir -p "$target"

if [[ "$force" != "--force" ]] && find "$target" -mindepth 1 -maxdepth 1 | read -r _; then
  printf 'Target directory is not empty: %s\n' "$target" >&2
  printf 'Use --force to copy into an existing directory.\n' >&2
  exit 1
fi

cp -R "$TEMPLATE_DIR/." "$target/"

printf 'Initialized problem-solution knowledge base: %s\n' "$target"
printf 'Configure it with:\n'
printf '  export PROBLEM_SOLUTION_KB_ROOT=%q\n' "$target"
printf 'or:\n'
printf '  printf %%s\\\\n %q > .problem-solution-root\n' "$target"

