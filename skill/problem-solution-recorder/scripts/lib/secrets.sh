# shellcheck shell=bash
# Shared secret-detection rules.
#
# Used by check-kb.sh and (vendored) by a knowledge base CLI so that the
# scanner behaves the same everywhere.
#
# Design notes:
# - `sk-` needs a left boundary, otherwise words like "task-polling-..."
#   look like keys.
# - session rules only match session_id/session_token/session_key with long
#   values, and exclude slash commands such as "/cross-session:check-inbox".
# - Exceptions are judged on the matched value, never on the path or the
#   whole line: a line may legitimately contain `[REDACTED]` next to a real
#   secret, and a knowledge base may legitimately live under .../examples/.

# 由使用方读取；shellcheck 在库文件里看不到引用。
# shellcheck disable=SC2034
PSR_SECRET_PATTERN='(^|[^A-Za-z0-9_-])sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{20,}|Bearer[[:space:]]+[A-Za-z0-9._~+/=-]{30,}|BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY|password[[:space:]]*[:=][[:space:]]*[^[:space:]]{8,}|passwd[[:space:]]*[:=][[:space:]]*[^[:space:]]{8,}|cookie[[:space:]]*[:=][[:space:]]*[^[:space:]]{20,}|(^|[^A-Za-z0-9_/-])session[_-]?(id|token|key)[[:space:]]*[:=][[:space:]]*[A-Za-z0-9._~+/=-]{24,}'

# 0 = benign (skip), 1 = report.
psr_secret_is_benign() {
  local value="$1"
  local pat
  case "$value" in
    *REDACTED*|*'<'*'>'*) return 0 ;;
  esac
  if printf '%s' "$value" | grep -qiE 'example|your[_-]|xxx|placeholder|dummy|masked|fixture|fake[_-]?key|content[-_]?url|local-only'; then
    return 0
  fi
  for pat in ${PSR_SECRET_ALLOW[@]+"${PSR_SECRET_ALLOW[@]}"}; do
    if printf '%s' "$value" | grep -qE -- "$pat"; then
      return 0
    fi
  done
  return 1
}

# Print a value with only the first and last four characters visible.
psr_secret_mask() {
  local value="$1"
  local secret="$value"
  case "$value" in
    *PRIVATE\ KEY*) printf '%s' "$value"; return 0 ;;
  esac
  case "$value" in
    *[:=]*) secret="${value#*[:=]}"; secret="${secret# }" ;;
  esac
  if [[ ${#secret} -le 8 ]]; then
    printf '<redacted>'
    return 0
  fi
  printf '%s…%s' "${secret:0:4}" "${secret: -4}"
}
