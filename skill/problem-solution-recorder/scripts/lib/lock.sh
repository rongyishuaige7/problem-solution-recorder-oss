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
#   - Every lock/reclaim directory carries a `token` file (`<pid>:<random>`)
#     written immediately after mkdir. Tokens identify a concrete instance.
#   - A stale lock is reclaimed only when it is older than 300s AND its pid is
#     no longer alive.
#   - Reclaiming is itself serialized by <lock>.reclaim (mkdir is the mutex).
#   - Removing either directory goes through `psr_lock_drop_instance`: the
#     directory is first *renamed* to a unique quarantine name (atomic), then
#     its token is compared with the observed one. A mismatch means the
#     instance was replaced in the meantime, so it is put back instead of
#     deleted. Read-then-`rm -rf` is never used on a path another process may
#     have re-created.
#   - A reclaim marker with a live owner is never removed, regardless of age;
#     only a confirmed-dead owner, or a marker that never got a pid and is
#     older than 60s, is dropped.
#   - Release only removes the lock when its token still matches ours.
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

psr_lock_token_pid() {
  local token="$1"
  printf '%s' "${token%%:*}"
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

# 只有“移走后再核对 token 仍然一致”才真正删除；否则原样放回。
# 返回 0 表示确实删除了 $2 这个实例；1 表示实例已变或删除失败。
psr_lock_drop_instance() {
  local dir="$1"
  local expect="$2"
  local quarantine="$dir.dropping.$$.$RANDOM"
  local got=""

  mv "$dir" "$quarantine" 2>/dev/null || return 1
  got="$(psr_lock_token_of "$quarantine")"

  if [[ "$got" == "$expect" ]]; then
    rm -rf "$quarantine" 2>/dev/null || true
    return 0
  fi

  # 不是我们观察到的实例：放回去，绝不能删掉别人刚建立的活锁/活标记。
  # 放回失败说明该路径已被新实例占用；此时保留隔离目录，不删除。
  mv "$quarantine" "$dir" 2>/dev/null || true
  return 1
}

psr_lock_acquire() {
  local root="$1"
  local retries="${2:-${PSR_LOCK_RETRIES:-50}}"
  local lock="$root/$PSR_LOCK_NAME"
  local reclaim="$lock.reclaim"
  local waited=0

  # 同进程可重入：调用方（例如 new-record → summary）已经持锁时不再等待。
  if [[ -f "$lock/token" ]]; then
    local held_token
    held_token="$(psr_lock_token_of "$lock")"
    if [[ "$(psr_lock_token_pid "$held_token")" == "$$" ]]; then
      PSR_LOCK_HELD=1
      PSR_LOCK_TOKEN="$held_token"
      return 0
    fi
  fi

  while :; do
    if mkdir "$lock" 2>/dev/null; then
      PSR_LOCK_TOKEN="$(psr_lock_new_token)"
      printf '%s\n' "$$" > "$lock/pid"
      printf '%s\n' "$PSR_LOCK_TOKEN" > "$lock/token"
      PSR_LOCK_HELD=1
      return 0
    fi

    if [[ -d "$lock" ]]; then
      # 回收者崩溃留下的标记会永久阻塞回收：所有者已死或标记从未写入 pid 时清理。
      if [[ -d "$reclaim" ]]; then
        local rpid="" rage=0 rtoken=""
        if [[ -f "$reclaim/pid" ]]; then
          rpid="$(cat "$reclaim/pid" 2>/dev/null || true)"
        fi
        rtoken="$(psr_lock_token_of "$reclaim")"
        rage=$(( $(date +%s) - $(psr_lock_mtime "$reclaim") ))
        [[ "$rage" -lt 0 ]] && rage=0
        if [[ -n "$rpid" ]]; then
          # 有 owner 时只能按“确证死亡”回收：活着的回收者即使暂停很久也不能抢。
          if ! kill -0 "$rpid" 2>/dev/null; then
            psr_lock_drop_instance "$reclaim" "$rtoken" || true
          fi
        elif [[ "$rage" -gt 60 ]]; then
          # 没有 owner 文件 = 回收者在写 pid 之前崩溃；只有这种窗口才按时间清理。
          psr_lock_drop_instance "$reclaim" "$rtoken" || true
        fi
      fi

      if psr_lock_is_stale "$lock"; then
        local lock_token
        lock_token="$(psr_lock_token_of "$lock")"

        # 只有拿到 .reclaim 的进程可以回收；其他进程继续等待。
        if mkdir "$reclaim" 2>/dev/null; then
          local my_token
          my_token="$(psr_lock_new_token)"
          printf '%s\n' "$$" > "$reclaim/pid" 2>/dev/null || true
          printf '%s\n' "$my_token" > "$reclaim/token" 2>/dev/null || true

          if [[ -n "${PSR_LOCK_TEST_PAUSE:-}" ]]; then
            # 仅用于回归测试固定交错窗口；默认不生效。
            sleep "$PSR_LOCK_TEST_PAUSE"
          fi

          # 重新确认：仍是同一个陈旧实例（token 未变）才删除。
          if [[ -d "$lock" ]] \
            && [[ "$(psr_lock_token_of "$lock")" == "$lock_token" ]] \
            && psr_lock_is_stale "$lock"; then
            printf 'Removing stale lock: %s\n' "$lock" >&2
            psr_lock_drop_instance "$lock" "$lock_token" || true
          fi

          # 只清理自己的标记（token 一致才删）。
          psr_lock_drop_instance "$reclaim" "$my_token" || true
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
    fi

    sleep 0.2
    waited=$(( waited + 1 ))
    if [[ "$waited" -gt "$retries" ]]; then
      printf 'Another writer holds the lock: %s\n' "$lock" >&2
      printf 'If no other process is running, remove it manually.\n' >&2
      return 1
    fi
  done
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

  # 自己持有的锁：token 已核对，直接删除即可（mv 仅用于“删别人可能重建的实例”）。
  rm -rf "$lock" 2>/dev/null || true
  PSR_LOCK_HELD=0
  PSR_LOCK_TOKEN=""
  return 0
}
