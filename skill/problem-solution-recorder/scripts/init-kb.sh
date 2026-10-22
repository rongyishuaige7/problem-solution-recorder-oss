#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$( ( unset CDPATH; cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P ) )"
SKILL_DIR="$( ( unset CDPATH; cd -P -- "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd -P ) )"
TEMPLATE_DIR="$SKILL_DIR/assets/minimal-knowledge-base"

usage() {
  cat <<'EOF'
Initialize a problem-solution knowledge base from the bundled template.

Usage:
  init-kb.sh /path/to/problem-solution-kb [--force] [--dry-run]

Behavior:
  - Refuses to write into a non-empty directory unless --force is given.
  - With --force, existing files that the template would overwrite are listed
    and copied into <target>/.psr-backup-<timestamp>/ first.
  - --dry-run prints the plan without writing anything.
EOF
}

target=""
force=0
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) force=1 ;;
    --dry-run) dry_run=1 ;;
    -h|--help) usage; exit 0 ;;
    *)
      if [[ -z "$target" ]]; then
        target="$1"
      else
        printf 'Unexpected argument: %s\n' "$1" >&2
        usage >&2
        exit 2
      fi
      ;;
  esac
  shift
done

if [[ -z "$target" ]]; then
  usage >&2
  exit 2
fi

[[ -d "$TEMPLATE_DIR" ]] || {
  printf 'Template directory not found: %s\n' "$TEMPLATE_DIR" >&2
  exit 1
}

if [[ -e "$target" && ! -d "$target" ]]; then
  printf 'Target exists and is not a directory: %s\n' "$target" >&2
  exit 1
fi

# 目录判空不使用管道：`find | read` 在 pipefail 下会把 find 的 SIGPIPE 当成成功，
# 从而漏掉“目录非空”这个事实。
first_entry=""
if [[ -d "$target" ]]; then
  first_entry="$(find "$target" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null || true)"
fi

if [[ -n "$first_entry" && "$force" -eq 0 ]]; then
  printf 'Target directory is not empty: %s\n' "$target" >&2
  printf 'Use --force to copy into an existing directory (existing files are backed up first).\n' >&2
  exit 1
fi

# 计算会被覆盖的文件（模板里有、目标里也有）
conflicts=""
if [[ -n "$first_entry" ]]; then
  conflicts="$(
    ( cd "$TEMPLATE_DIR" && find . -type f -print ) | sed 's|^\./||' | sort | while IFS= read -r rel; do
      # 用 if 而不是 `[[ ... ]] && ...`：后者在最后一个文件不冲突时返回 1，
      # 配合 pipefail 会让整个赋值失败。
      if [[ -e "$target/$rel" ]]; then
        printf '%s\n' "$rel"
      fi
    done
  )"
fi

if [[ "$dry_run" -eq 1 ]]; then
  printf '[dry-run] would initialize: %s\n' "$target"
  if [[ -n "$conflicts" ]]; then
    printf '[dry-run] would back up %s existing file(s) first:\n' "$(printf '%s\n' "$conflicts" | grep -c .)"
    printf '%s\n' "$conflicts" | sed 's/^/  - /'
  fi
  exit 0
fi

mkdir -p "$target"

if [[ -n "$conflicts" ]]; then
  backup_dir="$target/.psr-backup-$(date +%Y%m%d-%H%M%S)"
  printf 'Existing files would be overwritten; backing up to %s\n' "$backup_dir"
  printf '%s\n' "$conflicts" | while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    mkdir -p "$backup_dir/$(dirname "$rel")"
    cp -p "$target/$rel" "$backup_dir/$rel"
    printf '  backed up: %s\n' "$rel"
  done
fi

cp -R "$TEMPLATE_DIR/." "$target/"

printf 'Initialized problem-solution knowledge base: %s\n' "$target"
printf 'Configure it with:\n'
printf '  export PROBLEM_SOLUTION_KB_ROOT=%q\n' "$target"
printf 'or:\n'
printf '  printf %%s\\\\n %q > .problem-solution-root\n' "$target"
