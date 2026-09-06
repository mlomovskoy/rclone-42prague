# Shared functions for setting/resetting/showing per-machine overrides in
# $CONFIG_PATH/42-common.local.sh. Sourced by 42sync_install.sh and 42sync
# (each exposes configure-set/configure-reset/configure-show verbs that just
# call these) -- never run directly, same category as
# 42-common.sh/42-completions.bash.
#
# Depends on 42-common.sh already being sourced first: OVERRIDES_PATH (the
# file these functions edit) and every variable in CONFIGURE_NAMES below
# come from there.

# Every setting these functions know how to touch, and the single source of
# truth for name validation. Keep in sync with
# bin/42-internal/defaults/42-common.local.sh if either changes. LOG_PATH/
# WORK_PATH are deliberately absent -- both are always derived from
# STATE_PATH, never independently configurable.
CONFIGURE_NAMES=(local-path remote-path config-path state-path keep-logs bin-path file-filters project-filters)

configure_to_var() { tr 'a-z-' 'A-Z_' <<<"$1"; }  # local-path -> LOCAL_PATH

configure_is_known() {
  local want="$1" n
  for n in "${CONFIGURE_NAMES[@]}"; do [[ "$(configure_to_var "$n")" == "$want" ]] && return 0; done
  return 1
}

# Drops any existing line (commented or not) for $1, so repeat calls never
# pile up duplicate assignments -- the header comment above them is untouched
# since it never matches this pattern.
configure_strip_var() {
  local var="$1" tmp
  tmp="$(mktemp)"
  grep -vE "^#?[[:space:]]*${var}=" "$OVERRIDES_PATH" > "$tmp" || true
  mv "$tmp" "$OVERRIDES_PATH"
}

configure_set() {
  local name="$1" value="$2" var
  var="$(configure_to_var "$name")"
  configure_is_known "$var" || die "Unknown name '$name'. Run with no arguments to see the list."
  configure_strip_var "$var"
  printf '%s="%s"\n' "$var" "$value" >> "$OVERRIDES_PATH"
  echo "Set $var=\"$value\" in ${OVERRIDES_PATH/#$HOME/\~}"
}

configure_reset() {
  local name="$1" var
  var="$(configure_to_var "$name")"
  configure_is_known "$var" || die "Unknown name '$name'. Run with no arguments to see the list."
  configure_strip_var "$var"
  echo "Reset $var to its default in ${OVERRIDES_PATH/#$HOME/\~}"
}

configure_show() {
  local n var
  for n in "${CONFIGURE_NAMES[@]}"; do
    var="$(configure_to_var "$n")"
    printf '%-14s %s\n' "$var" "${!var}"
  done
}
