#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Resolve a problem-solution knowledge base root.

Usage:
  resolve-kb-root.sh [explicit-path] [--explain]

Resolution order:
  1. explicit-path argument
  2. PROBLEM_SOLUTION_KB_ROOT
  3. .problem-solution-root in cwd or a parent directory
  4. the knowledge base that contains this script (vendored bin/)
  5. $XDG_CONFIG_HOME/problem-solution-recorder/root
  6. ~/.config/problem-solution-recorder/root

--explain prints "<root>\t<source>" so callers can show where the
configuration came from (env, marker:<file>, xdg:<file>, arg).
EOF
}

trim_file_value() {
  sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$1" | sed -n '1p'
}

validate_root() {
  local root="$1"
  local resolved=""
  [[ -n "$root" ]] || return 1
  [[ -d "$root" ]] || return 1
  resolved="$( ( unset CDPATH; cd -P -- "$root" >/dev/null 2>&1 && pwd -P ) )" || return 1
  [[ -f "$resolved/AI入口.md" ]] || return 1
  printf '%s\n' "$resolved"
}

explain=0
arg=""

for a in "$@"; do
  case "$a" in
    --explain) explain=1 ;;
    -h|--help) usage; exit 0 ;;
    *)
      if [[ -z "$arg" ]]; then
        arg="$a"
      else
        printf 'Unexpected argument: %s\n' "$a" >&2
        exit 2
      fi
      ;;
  esac
done

emit() {
  local root="$1"
  local source="$2"
  if [[ "$explain" -eq 1 ]]; then
    printf '%s\t%s\n' "$root" "$source"
  else
    printf '%s\n' "$root"
  fi
}

if [[ -n "$arg" ]]; then
  if resolved="$(validate_root "$arg")"; then
    emit "$resolved" "arg"
    exit 0
  fi
  printf 'Invalid knowledge base root: %s\n' "$arg" >&2
  exit 1
fi

if [[ "${PROBLEM_SOLUTION_KB_ROOT:-}" != "" ]]; then
  if resolved="$(validate_root "$PROBLEM_SOLUTION_KB_ROOT")"; then
    emit "$resolved" "env"
    exit 0
  fi
  printf 'PROBLEM_SOLUTION_KB_ROOT is set but invalid: %s\n' "$PROBLEM_SOLUTION_KB_ROOT" >&2
  exit 1
fi

dir="$PWD"
while :; do
  marker="$dir/.problem-solution-root"
  if [[ -f "$marker" ]]; then
    root="$(trim_file_value "$marker")"
    # 相对路径按 marker 所在目录解析，而不是当前工作目录。
    case "$root" in
      /*) ;;
      "") ;;
      *) root="$dir/$root" ;;
    esac
    if resolved="$(validate_root "$root")"; then
      emit "$resolved" "marker:$marker"
      exit 0
    fi
    printf 'Marker file exists but points to an invalid root: %s\n' "$marker" >&2
    exit 1
  fi
  [[ "$dir" == "/" ]] && break
  dir="$(dirname "$dir")"
done

# 脚本随知识库分发时（<kb>/bin/…），优先管理它所在的知识库。
script_dir="$( ( unset CDPATH; cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P ) )"
self_root="$(dirname "$script_dir")"
if [[ -f "$self_root/AI入口.md" && -f "$self_root/INDEX.md" ]]; then
  emit "$self_root" "self"
  exit 0
fi

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
for config_file in "$config_home/problem-solution-recorder/root" "$HOME/.config/problem-solution-recorder/root"; do
  [[ -f "$config_file" ]] || continue
  root="$(trim_file_value "$config_file")"
  case "$root" in
    /*) ;;
    "") ;;
    *) root="$(dirname "$config_file")/$root" ;;
  esac
  if resolved="$(validate_root "$root")"; then
    emit "$resolved" "xdg:$config_file"
    exit 0
  fi
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
