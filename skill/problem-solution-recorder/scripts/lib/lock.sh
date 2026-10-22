# shellcheck shell=bash
# Shared write lock for a problem-solution knowledge base.
#
# Source this file, then:
#   psr_lock_acquire "$root" [retries]
#   trap 'psr_lock_release "$root"' EXIT
#   trap 'psr_lock_release "$root"; exit 130' INT TERM HUP
#
# Rules:
#   - The lock directory is <root>/.psr.lock, shared by every writer
#     (skill scripts and the knowledge base's own CLI).
#   - A stale lock is removed only when it is older than 300s AND its pid
#     is no longer alive.
#   - Release only removes the lock when the pid file still holds this
#     process id, so a process that lost its lock cannot delete someone
#     else's.
#   - PSR_LOCK_RETRIES (default 50, 0.2s each) controls how long to wait.

PSR_LOCK_NAME=".psr.lock"
PSR_LOCK_HELD=0

psr_lock_mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || printf '0'
}

psr_lock_acquire() {
  local root="$1"
  local retries="${2:-${PSR_LOCK_RETRIES:-50}}"
  local lock="$root/$PSR_LOCK_NAME"
  local waited=0 age now pid

  # 同进程可重入：调用方（例如 new-record → summary）已经持锁时不再等待。
  if [[ -f "$lock/pid" ]] && [[ "$(cat "$lock/pid" 2>/dev/null || true)" == "$$" ]]; then
    PSR_LOCK_HELD=1
    return 0
  fi

  while ! mkdir "$lock" 2>/dev/null; do
    if [[ -d "$lock" ]]; then
      now="$(date +%s)"
      age=$(( now - $(psr_lock_mtime "$lock") ))
      [[ "$age" -lt 0 ]] && age=0
      pid=""
      [[ -f "$lock/pid" ]] && pid="$(cat "$lock/pid" 2>/dev/null || true)"
      if [[ "$age" -gt 300 ]]; then
        if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
          printf 'Removing stale lock (age %ss, pid %s): %s\n' "$age" "${pid:-unknown}" "$lock" >&2
          rm -rf "$lock" 2>/dev/null || true
          continue
        fi
      fi
    fi
    sleep 0.2
    waited=$(( waited + 1 ))
    if [[ "$waited" -gt "$retries" ]]; then
      printf 'Another writer holds the lock: %s\n' "$lock" >&2
      printf 'If no other process is running, remove it manually.\n' >&2
      return 1
    fi
  done

  printf '%s\n' "$$" > "$lock/pid"
  PSR_LOCK_HELD=1
  return 0
}

psr_lock_release() {
  local root="$1"
  local lock="$root/$PSR_LOCK_NAME"
  local pid=""

  [[ "$PSR_LOCK_HELD" -eq 1 ]] || return 0
  [[ -d "$lock" ]] || { PSR_LOCK_HELD=0; return 0; }

  pid="$(cat "$lock/pid" 2>/dev/null || true)"
  if [[ "$pid" != "$$" ]]; then
    # 锁已被其他进程接管：不要删除别人的锁。
    PSR_LOCK_HELD=0
    return 0
  fi

  rm -rf "$lock" 2>/dev/null || true
  PSR_LOCK_HELD=0
  return 0
}
