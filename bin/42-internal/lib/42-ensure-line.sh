# Shared by 42sync_install.sh and 42password: makes sure exactly one line
# matching a given pattern is present in a shell rc file (or similar),
# equal to the current, correct value -- replacing any DIFFERENT line that
# already matches that pattern, rather than leaving it in place and
# appending a second one alongside it.
#
# The bug this fixes, confirmed to actually happen: the original version of
# this function only ever checked whether the exact target line was already
# present, and appended it if not. That's correct on a first install, but
# means any value derived from something a `configure-set` override can
# change (BIN_PATH's PATH/completions lines, 42password's
# RCLONE_PASSWORD_COMMAND line) leaves the OLD line sitting in the file
# forever once the underlying value changes -- a stale `source` line
# pointing at a since-moved completions file, a second PATH entry, a second
# password-command export shadowing the first. Confirmed by reproducing it
# directly: changing bin-path and reinstalling left two of each line behind.
#
# $pattern must be a grep -E pattern specific enough to match ONLY lines
# this toolkit itself would ever write for this one setting -- broad enough
# to catch an old value, never so broad it touches a user's own unrelated
# content in the same file. Each call site owns getting this right; this
# function has no way to verify it.

count_line() {  # file line -> how many exact matches
  [[ -f "$1" ]] || { echo 0; return 0; }
  grep -Fxc -- "$2" "$1" 2>/dev/null || true
}

ensure_line() {  # file pattern line description
  local file="$1" pattern="$2" line="$3" what="$4" n other_count
  n="$(count_line "$file" "$line")"
  if (( n > 1 )); then
    yellow "duplicate  $what appears $n times in ${file/#$HOME/\~} — harmless, but tidy it up"
    return 0
  fi
  if (( n == 1 )); then
    green "ok         $what already in ${file/#$HOME/\~}"
    return 0
  fi

  # The exact line isn't there. Is an OLDER version of it (matching the
  # pattern but not equal to $line)? If so this is an update, not a fresh
  # add -- replace it instead of appending alongside it.
  other_count=0
  [[ -f "$file" ]] && other_count="$(grep -cE -- "$pattern" "$file" 2>/dev/null || true)"

  if (( DRY )); then
    if (( other_count > 0 )); then
      yellow "would update  $what in ${file/#$HOME/\~}"
    else
      yellow "would add  $what to ${file/#$HOME/\~}"
    fi
    return 0
  fi

  if (( other_count > 0 )); then
    local tmp
    tmp="$(mktemp)"
    grep -vE -- "$pattern" "$file" > "$tmp"
    mv "$tmp" "$file"
    printf '%s\n' "$line" >> "$file"
    green "updated    $what in ${file/#$HOME/\~}"
  else
    printf '%s\n' "$line" >> "$file"
    green "added      $what to ${file/#$HOME/\~}"
  fi
}
