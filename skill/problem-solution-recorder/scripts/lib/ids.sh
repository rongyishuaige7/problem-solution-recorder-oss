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
  local max=0 f base n list

  if [[ -d "$dir" ]]; then
    list="$(mktemp "${TMPDIR:-/tmp}/psr-ids.XXXXXX")"
    if ! psr_list_records "$dir" "$list"; then
      rm -f "$list"
      printf 'psr: could not enumerate %s; refusing to allocate an id\n' "$dir" >&2
      return 2
    fi
    while IFS= read -r f; do
      base="${f##*/}"
      n="$(printf '%s' "$base" | sed -n -E "s/^${date}-([0-9]{3,})-.*/\1/p")"
      [[ -n "$n" ]] || continue
      (( 10#$n > max )) && max=$((10#$n))
    done < "$list"
    rm -f "$list"
  fi

  printf '%s-%03d' "$date" "$(( max + 1 ))"
}
