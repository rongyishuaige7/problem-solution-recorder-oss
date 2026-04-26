#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Resolve a problem-solution knowledge base root.

Usage:
  resolve-kb-root.sh [explicit-path]

Resolution order:
  1. explicit-path argument
  2. PROBLEM_SOLUTION_KB_ROOT
  3. .problem-solution-root in cwd or a parent directory
  4. $XDG_CONFIG_HOME/problem-solution-recorder/root
  5. ~/.config/problem-solution-recorder/root
EOF
}

trim_file_value() {
  sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$1" | sed -n '1p'
}

validate_root() {
  local root="$1"
  [[ -n "$root" ]] || return 1
  [[ -d "$root" ]] || return 1
  [[ -f "$root/AI入口.md" ]] || return 1
  printf '%s\n' "$root"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" != "" ]]; then
  validate_root "$1" && exit 0
  printf 'Invalid knowledge base root: %s\n' "$1" >&2
  exit 1
fi

if [[ "${PROBLEM_SOLUTION_KB_ROOT:-}" != "" ]]; then
  validate_root "$PROBLEM_SOLUTION_KB_ROOT" && exit 0
  printf 'PROBLEM_SOLUTION_KB_ROOT is set but invalid: %s\n' "$PROBLEM_SOLUTION_KB_ROOT" >&2
  exit 1
fi

dir="$PWD"
while :; do
  marker="$dir/.problem-solution-root"
  if [[ -f "$marker" ]]; then
    root="$(trim_file_value "$marker")"
    validate_root "$root" && exit 0
    printf 'Marker file exists but points to an invalid root: %s\n' "$marker" >&2
    exit 1
  fi
  [[ "$dir" == "/" ]] && break
  dir="$(dirname "$dir")"
done

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
for config_file in "$config_home/problem-solution-recorder/root" "$HOME/.config/problem-solution-recorder/root"; do
  [[ -f "$config_file" ]] || continue
  root="$(trim_file_value "$config_file")"
  validate_root "$root" && exit 0
  printf 'Config file exists but points to an invalid root: %s\n' "$config_file" >&2
  exit 1
done

cat >&2 <<'EOF'
No problem-solution knowledge base root found.

Set one of:
  export PROBLEM_SOLUTION_KB_ROOT="/path/to/problem-solution-kb"
  echo "/path/to/problem-solution-kb" > .problem-solution-root
  echo "/path/to/problem-solution-kb" > ~/.config/problem-solution-recorder/root

Or initialize a new repository with:
  init-kb.sh /path/to/problem-solution-kb
EOF
exit 1

