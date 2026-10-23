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
#   - Reclaiming a stale lock is itself mutual-exclusive: a reclaimer must
#     create <lock>.reclaim, then re-check that the lock it is about to delete
#     is still the same stale instance. Without that step two reclaimers could
#     both delete, and the later one would remove the fresh lock created by
#     the earlier one.
#   - Release only removes the lock when the pid file still holds this
#     process id, so a process that lost its lock cannot delete someone
#     else's.
#   - PSR_LOCK_RETRIES (default 50, 0.2s each) controls how long to wait.

PSR_LOCK_NAME=".psr.lock"
PSR_LOCK_HELD=0

psr_lock_mtime() {
  local m=""
  # GNU stat 用 -c，BSD/macOS 用 -f；GNU 的 -f 是“文件系统状态”，
  # 直接把它当 mtime 会得到非数字并让算术表达式报错。
  m="$(stat -c %Y "$1" 2>/dev/null)" || m=""
  if [[ -z "$m" ]]; then
    m="$(stat -f %m "$1" 2>/dev/null)" || m=""
  fi
  case "$m" in
    ''|*[!0-9]*) printf '0' ;;
    *) printf '%s' "$m" ;;
  esac
}

# 0 when the lock looks abandoned: older than 300s and its pid is gone.
psr_lock_is_stale() {
  local lock="$1"
  local now age mtime pid

  now="$(date +%s)"
  mtime="$(psr_lock_mtime "$lock")"
  # mtime 未知时不要当成“很旧”：否则会在持有者刚建目录、还没写 pid 的
  # 微秒窗口里误删活跃锁。
  if [[ "$mtime" -eq 0 ]]; then
    age=0
  else
    age=$(( now - mtime ))
    [[ "$age" -lt 0 ]] && age=0
  fi
  [[ "$age" -gt 300 ]] || return 1

  pid=""
  if [[ -f "$lock/pid" ]]; then
    pid="$(cat "$lock/pid" 2>/dev/null || true)"
  fi
  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" 2>/dev/null && return 1
  return 0
}

psr_lock_acquire() {
  local root="$1"
  local retries="${2:-${PSR_LOCK_RETRIES:-50}}"
  local lock="$root/$PSR_LOCK_NAME"
  local reclaim="$lock.reclaim"
  local waited=0

  # 同进程可重入：调用方（例如 new-record → summary）已经持锁时不再等待。
  if [[ -f "$lock/pid" ]] && [[ "$(cat "$lock/pid" 2>/dev/null || true)" == "$$" ]]; then
    PSR_LOCK_HELD=1
    return 0
  fi

  while :; do
    if mkdir "$lock" 2>/dev/null; then
      break
    fi

    if [[ -d "$lock" ]]; then
      if psr_lock_is_stale "$lock"; then
        # 只有拿到 .reclaim 的进程可以回收；其他进程继续等待。
        if mkdir "$reclaim" 2>/dev/null; then
          if [[ -n "${PSR_LOCK_TEST_PAUSE:-}" ]]; then
            # 仅用于回归测试固定交错窗口；默认不生效。
            sleep "$PSR_LOCK_TEST_PAUSE"
          fi
          # 重新确认：这段窗口里锁可能已被别的进程替换成活跃锁。
          if [[ -d "$lock" ]] && psr_lock_is_stale "$lock"; then
            printf 'Removing stale lock: %s\n' "$lock" >&2
            rm -rf "$lock" 2>/dev/null || true
          fi
          rmdir "$reclaim" 2>/dev/null || true
        fi

        waited=$(( waited + 1 ))
        if [[ "$waited" -gt "$retries" ]]; then
          printf 'Another writer holds the lock: %s\n' "$lock" >&2
          printf 'If no other process is running, remove it manually.\n' >&2
          return 1
        fi
        sleep 0.2
        continue
      fi

      # 回收者崩溃后留下的标记：超过 60s 允许任意等待者清理，避免永久卡死。
      if [[ -d "$reclaim" ]]; then
        local reclaim_age
        reclaim_age=$(( $(date +%s) - $(psr_lock_mtime "$reclaim") ))
        if [[ "$reclaim_age" -gt 60 ]]; then
          rmdir "$reclaim" 2>/dev/null || true
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
