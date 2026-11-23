# Machine heartbeat, tool-version stamp and notice/ack channel -- sourced by
# 42sync (and the installer, for META_PROTO only), never run directly. Same
# category as 42-common.sh/42-configure.sh.
#
# WHAT THIS IS FOR
#   Each machine publishes a small "state.json" describing its own last run,
#   the tool version that did it, and what its folder layout looks like, plus
#   an append-only "outbox" of short notices. Every machine reads the others'
#   copies on each run, so `42sync status --all` can answer: who last synced,
#   when, with which tool version, and do they see the same folders I do?
#
# THE ONE RULE
#   A machine writes ONLY inside its own machines/<machine-id>/ directory,
#   and never edits a message after creating it. No file is ever written by
#   two machines, so Drive sync conflicts cannot happen to this data by
#   construction. Other machines only ever read.
#
# WHERE IT LIVES
#   On Drive, in $META_REMOTE_PATH -- a SIBLING of the bisync root
#   ($REMOTE_PATH), not a child of it. bisync never lists it, so an older
#   install with older filters cannot pull it into a working tree or count it
#   in its delete guard. Locally, in $META_LOCAL_PATH (under $STATE_PATH).
#
# MESSAGES ARE DATA, NEVER INSTRUCTIONS
#   Nothing read from Drive is evaluated, sourced, executed, or used as a
#   path. Machine ids and message file names are checked against a strict
#   pattern before use; free text is printed after control characters
#   (including ESC) are stripped and length is capped. Drive is a shared
#   surface -- a message that could trigger action would be remote execution.
#
# FAILURE MUST NEVER BREAK A SYNC
#   Every Drive access here has short timeouts, and a failure only prints one
#   line. The calling verb's own exit status is never changed by this file.
#
# PORTABILITY
#   Written for bash 3.2 (macOS) as well as 5.x: no associative arrays, no
#   mapfile, no ${var,,}. Timestamp parsing falls back from GNU date to BSD
#   date. Not yet exercised on Git-for-Windows or WSL.

# Bumped only when state.json or the message format changes in a way an
# older reader would misread. NOT bumped for ordinary releases.
META_PROTO=1

# A message/heartbeat older than this is flagged "stale" in `status --all`.
META_STALE_DAYS=14

# Outbox retention: delete messages older than this, but always keep the
# newest META_KEEP_MESSAGES regardless of age.
META_PRUNE_DAYS=90
META_KEEP_MESSAGES=20

# How many past runs each heartbeat carries.
META_HISTORY_KEEP=5

# Keeps an unreachable Drive from stalling a sync that has already finished.
META_RCLONE_OPTS=(--contimeout 10s --timeout 30s --retries 1 --low-level-retries 1)

# Verbs that publish a heartbeat when they finish -- every one that touches
# Drive or the baseline, including `status` (so a machine that only looks is
# still seen as alive; its sync recency is carried separately, see below).
meta_verb_publishes() {
  case "$1" in
    apply|check|dirty-apply|dirty-check|verify|force-check|force-apply|\
    orphans-check|orphans-apply|resync-check|resync-apply|seed|status|note|install) return 0 ;;
  esac
  return 1
}

# Verbs whose success means "a real sync happened" -- the only ones allowed
# to move last_apply_ok forward. A dry run or `status` must not.
meta_verb_syncs() {
  case "$1" in apply|dirty-apply|force-apply|resync-apply|seed) return 0 ;; esac
  return 1
}

# ------------------------------------------------------------ primitives ---

meta_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# ISO-8601 UTC ("2026-11-22T12:38:55Z") -> epoch seconds. GNU date first,
# then BSD (macOS). Prints nothing and returns 1 if neither can parse it.
meta_epoch() {
  local iso="$1" e
  [[ "$iso" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || return 1
  e=$(date -u -d "$iso" +%s 2>/dev/null) \
    || e=$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$iso" +%s 2>/dev/null) \
    || return 1
  printf '%s' "$e"
}

meta_iso_from_epoch() {
  date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null
}

meta_file_mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null
}

# 1234 seconds -> "20m"; a missing/unparseable input -> "never".
meta_age_from_iso() {
  local iso="$1" then now d
  [[ -n "$iso" ]] || { printf 'never'; return; }
  then=$(meta_epoch "$iso") || { printf '?'; return; }
  now=$(date -u +%s)
  d=$(( now - then ))
  (( d < 0 )) && d=0
  if   (( d < 90 ));      then printf '%ss' "$d"
  elif (( d < 5400 ));    then printf '%sm' $(( (d + 30) / 60 ))
  elif (( d < 129600 ));  then printf '%sh' $(( (d + 1800) / 3600 ))
  else                         printf '%sd' $(( (d + 43200) / 86400 )); fi
}

meta_age_days() {
  local then now
  then=$(meta_epoch "$1") || { printf '99999'; return; }
  now=$(date -u +%s)
  printf '%s' $(( (now - then) / 86400 ))
}

# Escape a string for use inside a JSON "..." value. Control characters are
# dropped rather than escaped -- nothing we publish legitimately has any.
meta_json_str() {
  printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# Reverse of the above, for values read back from our own files.
meta_json_unstr() {
  sed -e 's/\\"/"/g' -e 's/\\\\/\\/g'
}

# Value of a flat top-level string/number field from a state.json that THIS
# code wrote (one `"key": value,` per line). Prints nothing if absent.
# Deliberately not a general JSON parser -- see the file header on why
# nothing from Drive is ever interpreted beyond this.
meta_get() {
  local file="$1" key="$2"
  [[ -f "$file" ]] || return 0
  sed -nE "s/^[[:space:]]*\"$key\":[[:space:]]*\"(.*)\",?[[:space:]]*$/\1/p; s/^[[:space:]]*\"$key\":[[:space:]]*([0-9]+),?[[:space:]]*$/\1/p" "$file" \
    | head -n 1 | meta_json_unstr
}

# Items of an array this code wrote as `"key": [` / one `"item",` per line / `]`.
meta_get_list() {
  local file="$1" key="$2"
  [[ -f "$file" ]] || return 0
  sed -nE "/^[[:space:]]*\"$key\":[[:space:]]*\[/,/^[[:space:]]*\]/ s/^[[:space:]]*\"(.*)\",?[[:space:]]*$/\1/p" "$file" | meta_json_unstr
}

# Free text from Drive, made safe to print: control bytes (ESC included)
# stripped, length capped.
meta_clean() {
  LC_ALL=C tr -d '\000-\037\177' | cut -c1-"${1:-300}"
}

meta_hash() {
  if   command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -c1-16
  elif command -v shasum    >/dev/null 2>&1; then shasum -a 256 | cut -c1-16
  else cksum | tr ' ' '-'; fi
}

# Dotted-number compare: prints -1, 0 or 1. Anything that is not x.y.z
# (e.g. "unknown") compares as 0.0.0 so it can never look "newest".
meta_ver_cmp() {
  local a="$1" b="$2" i x y
  [[ "$a" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || a=0.0.0
  [[ "$b" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || b=0.0.0
  for i in 1 2 3; do
    x=$(printf '%s' "$a" | cut -d. -f$i); y=$(printf '%s' "$b" | cut -d. -f$i)
    (( 10#$x < 10#$y )) && { printf -- '-1'; return; }
    (( 10#$x > 10#$y )) && { printf '1'; return; }
  done
  printf '0'
}

# ---------------------------------------------------------- tool version ---

# Sets TOOL_VERSION, TOOL_COMMIT, TOOL_PROTO. Reads the stamp the installer
# wrote next to the scripts; run from a repo clone instead (no stamp), it
# derives the same values from the clone itself. The stamp is PARSED, not
# sourced -- it is a file on disk, but a stray edit must never execute.
meta_load_version() {
  TOOL_VERSION="unknown"; TOOL_COMMIT="unknown"; TOOL_PROTO="$META_PROTO"
  local stamp="$HELPERS_DIR/VERSION" root v c
  if [[ -f "$stamp" ]]; then
    v=$(sed -nE 's/^tool_version=([0-9A-Za-z.+-]{1,32})$/\1/p' "$stamp" | head -n 1)
    c=$(sed -nE 's/^tool_commit=([0-9A-Za-z.+-]{1,40})$/\1/p' "$stamp" | head -n 1)
    [[ -n "$v" ]] && TOOL_VERSION="$v"
    [[ -n "$c" ]] && TOOL_COMMIT="$c"
    return 0
  fi
  root="$(dirname "$(dirname "$HELPERS_DIR")")"
  if [[ -f "$root/VERSION" && -e "$root/.git" ]]; then
    v=$(sed -nE 's/^([0-9]+\.[0-9]+\.[0-9]+)[[:space:]]*$/\1/p' "$root/VERSION" | head -n 1)
    [[ -n "$v" ]] && TOOL_VERSION="$v"
    TOOL_COMMIT="$(meta_repo_commit "$root")"
  fi
}

# Short commit of a repo, with "+dirty" if its working tree has changes.
meta_repo_commit() {
  local root="$1" c
  c=$(git -C "$root" rev-parse --short HEAD 2>/dev/null) || { printf 'unknown'; return; }
  if [[ -n "$(git -C "$root" status --porcelain 2>/dev/null)" ]]; then c="$c+dirty"; fi
  printf '%s' "$c"
}

# ---------------------------------------------------------------- identity ---

# Random, generated once, never derived from the hostname: campus cluster
# hostnames change between logins and a laptop's is user-editable.
meta_machine_id() {
  local f="$META_LOCAL_PATH/id" id
  if [[ -f "$f" ]]; then
    id=$(head -n 1 "$f")
    [[ "$id" =~ ^[0-9a-f]{8}$ ]] && { printf '%s' "$id"; return; }
  fi
  mkdir -p "$META_LOCAL_PATH"
  id=$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')
  [[ "$id" =~ ^[0-9a-f]{8}$ ]] || id=$(printf '%08x' $(( ($(date +%s) * 7919 + $$) & 0xffffffff )))
  printf '%s\n' "$id" > "$f"
  printf '%s' "$id"
}

meta_label() {
  local l="${MACHINE_LABEL:-}"
  [[ -n "$l" ]] || l="$(uname -n 2>/dev/null | cut -d. -f1)"
  [[ -n "$l" ]] || l="unnamed"
  printf '%s' "$l" | LC_ALL=C tr -cd 'A-Za-z0-9._-' | cut -c1-40
}

meta_os() { uname -s 2>/dev/null | tr 'A-Z' 'a-z'; }

# ----------------------------------------------------------------- layout ---

# Directory names to depth 2 under $LOCAL_PATH, sorted, one per line. Does not
# descend into a git repo, and skips dot-directories (a bare `*/` glob never
# matches them). Depth 2 because the renames that broke a sync (a project
# folder renamed on one machine, not on Drive) happen one level below the top.
meta_layout_list() {
  local d name sub
  [[ -d "$LOCAL_PATH" ]] || return 0
  for d in "$LOCAL_PATH"/*/; do
    [[ -d "$d" ]] || continue
    d="${d%/}"; name="${d##*/}"
    printf '%s\n' "$name"
    [[ -e "$d/.git" ]] && continue
    for sub in "$d"/*/; do
      [[ -d "$sub" ]] || continue
      sub="${sub%/}"
      printf '%s/%s\n' "$name" "${sub##*/}"
    done
  done | LC_ALL=C sort
}

# ------------------------------------------------------------- state.json ---

# Newest bisync listing's mtime, as ISO, or empty if there is no baseline.
meta_baseline_at() {
  local f newest="" best=0 m
  for f in "$WORK_PATH"/*.lst; do
    [[ -f "$f" ]] || continue
    m=$(meta_file_mtime "$f") || continue
    (( m > best )) && { best=$m; newest=$f; }
  done
  [[ -n "$newest" ]] && meta_iso_from_epoch "$best"
}

# Build this machine's heartbeat. $1 verb, $2 exit code, $3 result word,
# $4 log file basename. Writes $META_LOCAL_PATH/state.json atomically.
# Emits the three tool-generated notices (layout-changed, tool-upgraded,
# guard-aborted) BEFORE overwriting, because they are defined as a change
# from the previous heartbeat.
meta_write_state() {
  local verb="$1" rc="$2" result="$3" logname="$4"
  local state="$META_LOCAL_PATH/state.json" tmp prev id now
  id="$(meta_machine_id)"; now="$(meta_now)"
  prev="$META_LOCAL_PATH/state.prev.json"
  [[ -f "$state" ]] && cp "$state" "$prev" || rm -f "$prev"

  local layout_list layout_hash
  layout_list="$(meta_layout_list)"
  layout_hash="sha256:$(printf '%s\n' "$layout_list" | meta_hash)"

  local last_ok baseline
  last_ok="$(meta_get "$prev" last_apply_ok)"
  if (( rc == 0 )) && meta_verb_syncs "$verb"; then last_ok="$now"; fi
  baseline="$(meta_baseline_at)"

  mkdir -p "$META_LOCAL_PATH/outbox"
  meta_emit_transition_notices "$prev" "$layout_hash" "$layout_list" "$verb" "$result"

  # The last META_HISTORY_KEEP runs, newest first, one plain string each
  # ("<time> <verb> <result> <exit> <version>"). state.json is overwritten
  # every run, so without this "last run failed" hides that the run before it
  # was a success. Messages are NOT repeated here: they already live, with
  # their own retention, in the outbox, and duplicating them would make a
  # reader see the same notice twice.
  local hist_entry hist
  hist_entry="$now $(meta_json_str "$verb") $(meta_json_str "$result") $rc $(meta_json_str "$TOOL_VERSION")"
  hist="$(printf '%s\n' "$hist_entry"; meta_get_list "$prev" history)"
  hist="$(printf '%s\n' "$hist" | sed '/^$/d' | head -n "$META_HISTORY_KEEP")"

  tmp="$(mktemp "$META_LOCAL_PATH/.state.XXXXXX")"
  {
    printf '{\n'
    printf '  "proto": %s,\n'          "$META_PROTO"
    printf '  "machine_id": "%s",\n'   "$id"
    printf '  "label": "%s",\n'        "$(meta_json_str "$(meta_label)")"
    printf '  "os": "%s",\n'           "$(meta_json_str "$(meta_os)")"
    printf '  "tool_version": "%s",\n' "$(meta_json_str "$TOOL_VERSION")"
    printf '  "tool_commit": "%s",\n'  "$(meta_json_str "$TOOL_COMMIT")"
    printf '  "last_run_verb": "%s",\n'   "$(meta_json_str "$verb")"
    printf '  "last_run_at": "%s",\n'     "$now"
    printf '  "last_run_result": "%s",\n' "$(meta_json_str "$result")"
    printf '  "last_run_exit": %s,\n'     "$rc"
    printf '  "last_run_log": "%s",\n'    "$(meta_json_str "$logname")"
    printf '  "last_apply_ok": "%s",\n'   "$last_ok"
    printf '  "baseline_at": "%s",\n'     "$baseline"
    printf '  "history": [\n'
    printf '%s\n' "$hist" | while IFS= read -r h; do printf '    "%s",\n' "$h"; done | sed '$ s/,$//'
    printf '  ],\n'
    printf '  "layout_hash": "%s",\n'     "$layout_hash"
    printf '  "layout_top": [\n'
    if [[ -n "$layout_list" ]]; then
      printf '%s\n' "$layout_list" | while IFS= read -r n; do
        printf '    "%s",\n' "$(meta_json_str "$n")"
      done | sed '$ s/,$//'
    fi
    printf '  ]\n'
    printf '}\n'
  } > "$tmp"
  mv "$tmp" "$state"
}

# -------------------------------------------------------------- messages ---

# Write one message into our own outbox. $1 type, $2 topic, $3 body JSON
# (already valid -- callers build it with meta_json_str). Never edits an
# existing file: the name carries a timestamp and random suffix.
meta_emit() {
  local type="$1" topic="$2" body="$3" id rnd f
  id="$(meta_machine_id)"
  rnd=$(od -An -N2 -tx1 /dev/urandom | tr -d ' \n')
  local mid; mid="$(date -u +%Y%m%dT%H%M%SZ)-$rnd"
  mkdir -p "$META_LOCAL_PATH/outbox"
  f="$META_LOCAL_PATH/outbox/$mid.json"
  printf '{"proto":%s,"id":"%s","from":"%s","label":"%s","tool_version":"%s","at":"%s","type":"%s","topic":"%s","body":%s}\n' \
    "$META_PROTO" "$mid" "$id" "$(meta_json_str "$(meta_label)")" "$(meta_json_str "$TOOL_VERSION")" \
    "$(meta_now)" "$(meta_json_str "$type")" "$(meta_json_str "$topic")" "$body" > "$f"
}

# JSON array of strings from newline-separated input, capped at 50 items.
meta_json_array() {
  local out="" n=0 line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    n=$((n + 1)); (( n > 50 )) && break
    out="$out${out:+,}\"$(meta_json_str "$line")\""
  done
  printf '[%s]' "$out"
}

meta_emit_transition_notices() {
  local prev="$1" new_hash="$2" new_list="$3" verb="$4" result="$5"
  local old_hash old_ver added removed
  old_hash="$(meta_get "$prev" layout_hash)"
  if [[ -n "$old_hash" && "$old_hash" != "$new_hash" ]]; then
    local oldf newf
    oldf="$(mktemp)"; newf="$(mktemp)"
    meta_get_list "$prev" layout_top | LC_ALL=C sort > "$oldf"
    printf '%s\n' "$new_list" | LC_ALL=C sort > "$newf"
    added="$(LC_ALL=C comm -13 "$oldf" "$newf" | meta_json_array)"
    removed="$(LC_ALL=C comm -23 "$oldf" "$newf" | meta_json_array)"
    rm -f "$oldf" "$newf"
    meta_emit notice layout-changed "{\"added\":$added,\"removed\":$removed}"
  fi
  old_ver="$(meta_get "$prev" tool_version)"
  local old_commit new_commit
  old_commit="$(meta_get "$prev" tool_commit)"; old_commit="${old_commit%+dirty}"
  new_commit="${TOOL_COMMIT%+dirty}"
  # A new version, or the same version from a different commit (a fix that
  # was not given a release number). "+dirty" alone is not an upgrade.
  if [[ -n "$old_ver" ]] && { [[ "$old_ver" != "$TOOL_VERSION" ]] || { [[ -n "$old_commit" && "$old_commit" != "unknown" && "$new_commit" != "unknown" && "$old_commit" != "$new_commit" ]]; }; }; then
    meta_emit notice tool-upgraded "{\"from\":\"$(meta_json_str "$old_ver")\",\"to\":\"$(meta_json_str "$TOOL_VERSION")\",\"from_commit\":\"$(meta_json_str "$old_commit")\",\"to_commit\":\"$(meta_json_str "$new_commit")\"}"
  fi
  if [[ "$result" == "guard-aborted" ]]; then
    local detail
    detail="$(grep -o 'too many deletes ([^)]*)' "${LOG:-/dev/null}" 2>/dev/null | head -n 1 | meta_clean 120)"
    meta_emit notice guard-aborted "{\"verb\":\"$(meta_json_str "$verb")\",\"detail\":\"$(meta_json_str "$detail")\"}"
  fi
}

# `42sync note "<text>"`
meta_note() {
  local text="$1"
  [[ -n "$text" ]] || return 1
  text="$(printf '%s' "$text" | meta_clean 500)"
  meta_emit notice note "{\"text\":\"$(meta_json_str "$text")\"}"
}

# Keep the newest META_KEEP_MESSAGES; of the rest, drop those older than
# META_PRUNE_DAYS -- locally and on Drive. Own outbox only.
meta_prune_outbox() {
  local out="$META_LOCAL_PATH/outbox" f name id
  [[ -d "$out" ]] || return 0
  id="$(meta_machine_id)"
  ls -1 "$out" 2>/dev/null | LC_ALL=C sort -r | tail -n +$((META_KEEP_MESSAGES + 1)) | while IFS= read -r name; do
    [[ "$name" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{4}\.json$ ]] || continue
    if [[ -n "$(find "$out/$name" -mtime +"$META_PRUNE_DAYS" 2>/dev/null)" ]]; then
      rm -f "$out/$name"
      rclone deletefile "$META_REMOTE_PATH/machines/$id/outbox/$name" "${META_RCLONE_OPTS[@]}" >/dev/null 2>&1 || true
    fi
  done
}

# ------------------------------------------------------------ drive side ---

# Push our own directory (state.json + outbox). Returns rclone's status.
meta_push() {
  local id; id="$(meta_machine_id)"
  rclone copy "$META_LOCAL_PATH" "$META_REMOTE_PATH/machines/$id" \
    --filter '+ /state.json' --filter '+ /outbox/*.json' --filter '- **' \
    "${META_RCLONE_OPTS[@]}" >/dev/null 2>&1
}

# Pull everyone else's directories into seen/. `copy`, never `sync`: a
# machine that vanished from Drive keeps its last-known data here.
meta_fetch() {
  local id; id="$(meta_machine_id)"
  mkdir -p "$META_LOCAL_PATH/seen"
  rclone copy "$META_REMOTE_PATH/machines" "$META_LOCAL_PATH/seen" \
    --filter "- /$id/**" --filter '+ /*/state.json' --filter '+ /*/outbox/*.json' --filter '- **' \
    "${META_RCLONE_OPTS[@]}" >/dev/null 2>&1
}

# Machine-id directories under seen/ that pass the strict pattern. Our own
# id is skipped even if it somehow got fetched: a machine is never "another
# machine" to itself.
meta_seen_ids() {
  local d n me
  me="$(meta_machine_id)"
  for d in "$META_LOCAL_PATH"/seen/*/; do
    [[ -d "$d" ]] || continue
    n="${d%/}"; n="${n##*/}"
    [[ "$n" == "$me" ]] && continue
    [[ "$n" =~ ^[0-9a-f]{8}$ ]] && printf '%s\n' "$n"
  done
}

# Print unread notices from other machines, mark them read, and ack each.
# Returns the number shown via META_UNREAD_SHOWN.
meta_show_unread() {
  META_UNREAD_SHOWN=0
  local readlist="$META_LOCAL_PATH/read.list" mid f from at topic text label
  touch "$readlist"
  local sid
  for sid in $(meta_seen_ids); do
    for f in "$META_LOCAL_PATH/seen/$sid/outbox"/*.json; do
      [[ -f "$f" ]] || continue
      mid="${f##*/}"; mid="${mid%.json}"
      [[ "$mid" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{4}$ ]] || continue
      grep -qxF "$sid/$mid" "$readlist" && continue
      local line mtype
      line="$(head -n 1 "$f")"
      mtype="$(printf '%s' "$line" | sed -nE 's/.*"type":"([a-z]+)".*/\1/p')"
      printf '%s\n' "$sid/$mid" >> "$readlist"
      [[ "$mtype" == "notice" ]] || continue
      label="$(meta_get "$META_LOCAL_PATH/seen/$sid/state.json" label)"; [[ -n "$label" ]] || label="$sid"
      at="$(printf '%s' "$line" | sed -nE 's/.*"at":"([^"]*)".*/\1/p' | meta_clean 20)"
      topic="$(printf '%s' "$line" | sed -nE 's/.*"topic":"([^"]*)".*/\1/p' | meta_clean 40)"
      text="$(printf '%s' "$line" | sed -nE 's/.*"body":(.*)\}$/\1/p' | meta_clean 300)"
      # A free-text note reads better as its text than as raw JSON.
      if [[ "$topic" == note ]]; then
        text="$(printf '%s' "$text" | sed -nE 's/^\{"text":"(.*)"\}$/\1/p' | meta_json_unstr)"
      fi
      if (( META_UNREAD_SHOWN == 0 )); then echo; yellow "Notices from other machines:"; fi
      META_UNREAD_SHOWN=$((META_UNREAD_SHOWN + 1))
      printf '  [%s] %s (%s ago): %s\n' "$(printf '%s' "$label" | meta_clean 40)" "$topic" "$(meta_age_from_iso "$at")" "$text"
      meta_emit ack ack "{\"ack_of\":\"$(meta_json_str "$sid/$mid")\"}"
    done
  done
}

# ----------------------------------------------------------- the one call ---

# Called from the exit trap of every verb that publishes: write the heartbeat,
# push it, fetch the others', show unread notices. Never changes the verb's
# exit status and never fails loudly -- see the header.
meta_on_exit() {
  local verb="$1" rc="$2"
  (( META_ENABLED )) || return 0
  meta_verb_publishes "$verb" || return 0
  (( ${META_DONE:-0} )) && return 0
  META_DONE=1

  local result=ok
  if (( rc != 0 )); then
    if grep -q 'too many deletes' "${LOG:-/dev/null}" 2>/dev/null; then result=guard-aborted; else result=failed; fi
  fi

  meta_load_version
  mkdir -p "$META_LOCAL_PATH" 2>/dev/null || return 0
  meta_write_state "$verb" "$rc" "$result" "$(basename "${LOG:-}")" 2>/dev/null || { yellow "meta: could not write local heartbeat"; return 0; }
  meta_prune_outbox 2>/dev/null || true

  local pushed=0
  META_LAST_PUSHED=0
  if meta_push; then
    pushed=1; META_LAST_PUSHED=1
    logmsg "meta: published heartbeat $(meta_machine_id) result=$result"
  else
    yellow "meta: could not reach Drive to publish this machine's heartbeat (kept locally, will retry next run)"
    logmsg "meta: publish failed"
  fi
  # Fetching is attempted even if publishing failed (it may be a transient
  # error on one call) but only complained about once.
  if ! meta_fetch && (( pushed )); then
    yellow "meta: could not read other machines' data from Drive (showing last-known)"
  fi
  meta_show_unread

  # `status` sets META_REPORT so its table/footer is printed from the data
  # just fetched, rather than from the previous run's.
  case "${META_REPORT:-}" in
    table)  echo; meta_table ;;
    footer) meta_footer ;;
  esac
  return 0
}

# Called by the installer once new tools are in place, so an upgrade is itself
# visible to the other machines: a heartbeat with the new version and commit,
# plus a tool-upgraded notice naming where it came from. Silent and harmless
# on a machine with no Drive remote yet or with notices turned off. $1 is the
# directory holding the freshly written VERSION stamp.
meta_publish_install() {
  (( META_ENABLED )) || return 0
  [[ -f "$1/VERSION" ]] && HELPERS_DIR="$1"
  # No prompting: an encrypted rclone config with no password in this
  # environment must make this skip, never hang an install waiting on a tty.
  RCLONE_ASK_PASSWORD=false rclone listremotes 2>/dev/null | grep -qx 'gdrive:' || return 0
  RCLONE_ASK_PASSWORD=false meta_on_exit install 0
}

# --------------------------------------------------------------- reporting ---

# One line for the end of plain `status`: how many other machines, the most
# stale, anything wrong with versions. Reads whatever is in seen/ -- fetching
# is the caller's job.
meta_footer() {
  local sid n=0 oldest_age=-1 oldest_label="" newest_ver="$TOOL_VERSION" newest_label="" v age
  for sid in $(meta_seen_ids); do
    n=$((n + 1))
    local sf="$META_LOCAL_PATH/seen/$sid/state.json"
    age="$(meta_age_days "$(meta_get "$sf" last_run_at)")"
    (( age > oldest_age )) && { oldest_age=$age; oldest_label="$(meta_get "$sf" label)"; }
    v="$(meta_get "$sf" tool_version)"
    if [[ "$(meta_ver_cmp "$v" "$newest_ver")" == 1 ]]; then newest_ver="$v"; newest_label="$(meta_get "$sf" label)"; fi
  done
  echo
  if (( n == 0 )); then
    echo "Other machines: none have reported yet  (see: 42sync status --all)"
  else
    printf 'Other machines: %s reported; most stale: %s, last ran %sd ago' "$n" "${oldest_label:-?}" "$oldest_age"
    (( oldest_age >= META_STALE_DAYS )) && printf ' (STALE)'
    printf '\n'
  fi
  if [[ -n "$newest_label" ]]; then
    yellow "This install ($TOOL_VERSION) is older than $newest_label's ($newest_ver) -- update with: git pull && ./42sync_install.sh apply"
  fi
}

# `status --all`. Own row from the heartbeat just written, others from seen/.
meta_table() {
  local own_hash own="$META_LOCAL_PATH/state.json"
  own_hash="$(meta_get "$own" layout_hash)"
  printf '%-14s %-9s %-7s %-26s %-22s %-10s %s\n' MACHINE ID OS TOOL "LAST RUN" "LAST SYNC" LAYOUT
  local sid sf mark flags newest="$TOOL_VERSION" newest_label="" nv
  # Newest version anywhere, so every row (this machine's included) can be
  # flagged "outdated" against it.
  for sid in $(meta_seen_ids); do
    nv="$(meta_get "$META_LOCAL_PATH/seen/$sid/state.json" tool_version)"
    if [[ "$(meta_ver_cmp "$nv" "$newest")" == 1 ]]; then newest="$nv"; newest_label="$(meta_get "$META_LOCAL_PATH/seen/$sid/state.json" label)"; fi
  done
  local rows="$(meta_machine_id)"
  for sid in $rows $(meta_seen_ids); do
    if [[ "$sid" == "$(meta_machine_id)" ]]; then sf="$own"; mark="*"; else sf="$META_LOCAL_PATH/seen/$sid/state.json"; mark=""; fi
    [[ -f "$sf" ]] || continue
    local label os ver commit proto verb res at ok lay age
    proto="$(meta_get "$sf" proto)"
    label="$(meta_get "$sf" label | meta_clean 20)$mark"
    if [[ -n "$proto" ]] && (( proto > META_PROTO )); then
      printf '%-14s %-9s %s\n' "$label" "$sid" "speaks proto $proto, this install speaks $META_PROTO -- upgrade this install to read it"
      continue
    fi
    os="$(meta_get "$sf" os | meta_clean 7)"
    ver="$(meta_get "$sf" tool_version | meta_clean 12)"; commit="$(meta_get "$sf" tool_commit | meta_clean 16)"
    verb="$(meta_get "$sf" last_run_verb | meta_clean 14)"; res="$(meta_get "$sf" last_run_result | meta_clean 14)"
    at="$(meta_get "$sf" last_run_at)"; ok="$(meta_get "$sf" last_apply_ok)"
    age="$(meta_age_days "$at")"
    lay=same; [[ "$(meta_get "$sf" layout_hash)" == "$own_hash" ]] || lay=DIFFERS
    flags=""
    [[ "$(meta_ver_cmp "$ver" "$newest")" == -1 ]] && flags="$flags outdated"
    (( age >= META_STALE_DAYS )) && flags="$flags STALE"
    printf '%-14s %-9s %-7s %-26s %-22s %-10s %s%s\n' "$label" "$sid" "$os" "$ver ($commit)" \
      "$verb $res $(meta_age_from_iso "$at")" "$(meta_age_from_iso "$ok")" "$lay" "$flags"
  done
  echo
  echo "Recent runs (newest first):"
  for sid in $(meta_machine_id) $(meta_seen_ids); do
    if [[ "$sid" == "$(meta_machine_id)" ]]; then sf="$own"; else sf="$META_LOCAL_PATH/seen/$sid/state.json"; fi
    [[ -f "$sf" ]] || continue
    printf '  %s:\n' "$(meta_get "$sf" label | meta_clean 24)"
    meta_get_list "$sf" history | head -n 3 | while read -r t v r e ver; do
      printf '    %-12s %-9s %-14s exit %s  (%s)\n' "$(meta_age_from_iso "$t") ago" "$v" "$r" "$e" "$ver"
    done
  done
  echo
  echo "* = this machine.  LAST SYNC = last successful apply/seed/resync."
  if [[ -n "$newest_label" ]]; then
    yellow "This install ($TOOL_VERSION) is older than $newest_label's ($newest) -- update with: git pull && ./42sync_install.sh apply"
  fi
}
