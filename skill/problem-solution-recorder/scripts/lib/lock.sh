# shellcheck shell=bash
# Shared write lock for a problem-solution knowledge base.
#
# Source this file, then:
#   psr_lock_acquire "$root" [retries]
#   trap 'psr_lock_release "$root"' EXIT
#   trap 'psr_lock_release "$root"; exit 130' INT TERM HUP
#
# Design (why it is safe):
#   - Acquisition and stale-lock removal both run under `.psr.lock.guard`, a
#     second `mkdir` mutex held only for a few syscalls. Because a new writer
#     cannot create the lock without the guard, a reclaimer that checks a stale
#     lock can no longer race with a normal release + re-acquire: the handoff
#     is serialized too, not just reclaimer-vs-reclaimer.
#   - The lock path is never renamed or moved: removal happens in place while
#     holding the guard, so there is no window where the path is empty for
#     someone else to claim.
#   - The guard is never reclaimed automatically. A process killed exactly
#     inside the guard leaves it behind and blocks writes until a human removes
#     it; the timeout message prints the exact command, and doctor reports it.
#     That is a liveness cost, never a mutual-exclusion one.
#   - A stale lock is removed only when it is older than 300s AND its pid is
#     gone. Release only removes the lock when its `token` still matches ours.
#   - PSR_LOCK_RETRIES (default 50, 0.2s each) controls how long to wait.

PSR_LOCK_NAME=".psr.lock"
PSR_LOCK_HELD=0
PSR_LOCK_TOKEN=""

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

psr_lock_new_token() {
  printf '%s:%s%s' "$$" "$(date +%s)" "$RANDOM"
}

psr_lock_token_of() {
  local dir="$1"
  if [[ -f "$dir/token" ]]; then
    cat "$dir/token" 2>/dev/null || true
  fi
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

psr_lock_release() {
  local root="$1"
  local lock="$root/$PSR_LOCK_NAME"
  local token=""

  [[ "$PSR_LOCK_HELD" -eq 1 ]] || return 0
  [[ -d "$lock" ]] || { PSR_LOCK_HELD=0; PSR_LOCK_TOKEN=""; return 0; }

  token="$(psr_lock_token_of "$lock")"
  if [[ -z "$PSR_LOCK_TOKEN" || "$token" != "$PSR_LOCK_TOKEN" ]]; then
    # 锁已被其他进程接管：不要删除别人的锁。
    PSR_LOCK_HELD=0
    PSR_LOCK_TOKEN=""
    return 0
  fi

  rm -rf "$lock" 2>/dev/null || true
  PSR_LOCK_HELD=0
  PSR_LOCK_TOKEN=""
  return 0
}

psr_lock_acquire() {
  local root="$1"
  local retries="${2:-${PSR_LOCK_RETRIES:-50}}"
  local lock="$root/$PSR_LOCK_NAME"
  local guard="$lock.guard"
  local waited=0

  # 同进程可重入：调用方（例如 new-record → summary）已经持锁时不再等待。
  if [[ -f "$lock/token" ]]; then
    local held_token
    held_token="$(psr_lock_token_of "$lock")"
    if [[ "${held_token%%:*}" == "$$" ]]; then
      PSR_LOCK_HELD=1
      PSR_LOCK_TOKEN="$held_token"
      return 0
    fi
  fi

  while :; do
    # 取得 guard 才允许“检查/回收/创建”这三步；正常获取也走这里，
    # 因此回收者的判断不会与一次正常的释放+获取交接交错。
    if mkdir "$guard" 2>/dev/null; then
      # guard 也要有 owner：doctor 需要区分“活持有者暂停”和“残留 guard”。
      printf '%s\n' "$$" > "$guard/pid" 2>/dev/null || true
      printf '%s\n' "$(psr_lock_new_token)" > "$guard/token" 2>/dev/null || true
      if [[ -d "$lock" ]] && psr_lock_is_stale "$lock"; then
        if [[ -n "${PSR_LOCK_TEST_PAUSE_GUARD:-}" ]]; then
          # 仅用于回归测试放大“判断与删除之间”的窗口；默认不生效。
          sleep "$PSR_LOCK_TEST_PAUSE_GUARD"
        fi
        printf 'Removing stale lock: %s\n' "$lock" >&2
        rm -rf "$lock" 2>/dev/null || true
      fi

      if mkdir "$lock" 2>/dev/null; then
        PSR_LOCK_TOKEN="$(psr_lock_new_token)"
        printf '%s\n' "$$" > "$lock/pid"
        printf '%s\n' "$PSR_LOCK_TOKEN" > "$lock/token"
        rm -rf "$guard" 2>/dev/null || true
        PSR_LOCK_HELD=1
        return 0
      fi

      # 锁仍被占用（或刚好被抢占）：释放 guard 后等待。
      rm -rf "$guard" 2>/dev/null || true
    fi

    sleep 0.2
    waited=$(( waited + 1 ))
    if [[ "$waited" -gt "$retries" ]]; then
      printf 'Another writer holds the lock: %s\n' "$lock" >&2
      if [[ -d "$guard" ]]; then
        printf 'A reclaim guard is still present: %s\n' "$guard" >&2
      fi
      printf 'If no other process is running, remove them manually:\n' >&2
      printf '  rm -rf "%s" "%s"\n' "$lock" "$guard" >&2
      return 1
    fi
  done
}
