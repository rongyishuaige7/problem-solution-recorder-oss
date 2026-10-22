# shellcheck shell=bash
# Sequence allocation for record ids.
#
# Usage:
#   psr_next_id <records/year-dir> <YYYY-MM-DD>
# Prints YYYY-MM-DD-NNN (at least three digits, growing past 999).
#
# All writers (skill scripts and a knowledge base CLI) must use this so that
# the sequence rule lives in one place.

psr_next_id() {
  local dir="$1"
  local date="$2"
  local max=0 f base n

  if [[ -d "$dir" ]]; then
    while IFS= read -r f; do
      base="${f##*/}"
      n="$(printf '%s' "$base" | sed -n -E "s/^${date}-([0-9]{3,})-.*/\1/p")"
      [[ -n "$n" ]] || continue
      (( 10#$n > max )) && max=$((10#$n))
    done < <(find "$dir" -maxdepth 1 -type f -name "${date}-*.md" | sort)
  fi

  printf '%s-%03d' "$date" "$(( max + 1 ))"
}
