# Classifies a repo's git remotes by purpose.
#
# A single uniform rule ("any github.com remote is the trusted one") breaks
# for a fork (origin yours, upstream not) and for a clone of someone else's
# public repo (a github.com remote that isn't yours). So this splits the
# rule by what the remote is being used FOR, not by host alone:
#
#   bootstrap/clone source -- any github.com remote, preferring one the user
#                              owns if more than one qualifies
#   auto-pull sources      -- every remote, any host (picks up a teammate's
#                              push to a shared vogsphere repo, or upstream)
#   auto-push target       -- only github.com remote(s) the user owns, never
#                              anything else
#
# Used by 42sync's onboard-check/onboard-apply verbs. Run directly for a
# standalone check against a real repo:
#   bash bin/42-internal/lib/42-remote-classify.sh /path/to/repo

have() { command -v "$1" >/dev/null 2>&1; }

# "Owned by the user" must never be hardcoded -- this repo is meant to be
# cloned and reused by anyone with their own GitHub account. Derived live via
# `gh api user --jq .login` (gh's own built-in JSON filter -- no system jq
# dependency), memoized so a caller checking many repos in one run (a whole
# `42sync` pass) only pays the API call once, not once per repo.
#
# Not fatal if it can't be determined -- confirmed for real on this machine:
# gh can be installed but not yet `gh auth login`-ed, a real gap on any
# fresh machine. Every caller below degrades safely when this returns 1:
# classify_remotes() just never adds anything to REMOTE_PUSH, and falls back
# to "first github.com remote, unordered by ownership" for REMOTE_BOOTSTRAP.
GITHUB_OWNER=""
GITHUB_OWNER_CHECKED=0
github_owner() {  # sets GITHUB_OWNER; returns 1 if it could not be determined
  if (( GITHUB_OWNER_CHECKED )); then
    [[ -n "$GITHUB_OWNER" ]]
    return
  fi
  GITHUB_OWNER_CHECKED=1
  have gh || return 1
  GITHUB_OWNER="$(gh api user --jq .login 2>/dev/null)" || GITHUB_OWNER=""
  [[ -n "$GITHUB_OWNER" ]]
}

# Host from a remote URL, in any of the three shapes git actually uses:
#   scp-like    user@host:owner/repo.git       (vogsphere and github.com both
#                                                seen using this on this
#                                                machine's real repos)
#   scheme://   https://host/owner/repo.git    (.git suffix optional -- seen
#                                                both ways on this machine)
#   scheme://   ssh://user@host[:port]/owner/repo.git
# Not scoped to "git@" specifically for the scp-like case, even though
# that's the only user seen in practice here -- a self-hosted remote could
# plausibly use a different SSH user.
remote_host() {  # url
  local url="$1" rest
  case "$url" in
    *://*)
      rest="${url#*://}"; rest="${rest#*@}"; rest="${rest%%/*}"
      printf '%s\n' "${rest%%:*}"
      ;;
    *@*:*)
      rest="${url#*@}"
      printf '%s\n' "${rest%%:*}"
      ;;
    *)
      printf '%s\n' ""
      ;;
  esac
}

# The path segment right after the host -- for github.com, that's the owner
# (github.com/OWNER/repo or git@github.com:OWNER/repo). Same three URL
# shapes as remote_host(), kept as a separate function rather than one that
# returns both: a future caller of remote_host() alone shouldn't have to
# care about owner-segment parsing it doesn't need.
remote_owner_segment() {  # url
  local url="$1" rest
  case "$url" in
    *://*)
      rest="${url#*://}"; rest="${rest#*@}"; rest="${rest#*/}"
      ;;
    *@*:*)
      rest="${url#*@}"; rest="${rest#*:}"
      ;;
    *)
      rest=""
      ;;
  esac
  printf '%s\n' "${rest%%/*}"
}

# Sets REMOTE_NAMES (every remote), REMOTE_BOOTSTRAP (one name or empty),
# REMOTE_PULL (array, == REMOTE_NAMES today -- kept separate since "pull"
# and "every remote" are different concepts that only happen to coincide
# under the current decision), and REMOTE_PUSH (array). Not value-returning
# (same reasoning as detect_rclone/detect_gh in 42sync_install.sh): callers
# need multiple outputs, and a command-substitution caller would only see a
# subshell's copy of these globals.
REMOTE_NAMES=()
REMOTE_BOOTSTRAP=""
REMOTE_PULL=()
REMOTE_PUSH=()
classify_remotes() {  # repo-path
  local repo="$1" name url host owner
  local -a github_remotes=() github_owned=()

  REMOTE_NAMES=(); REMOTE_BOOTSTRAP=""; REMOTE_PULL=(); REMOTE_PUSH=()

  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    REMOTE_NAMES+=("$name")
    REMOTE_PULL+=("$name")  # every remote, any host -- the pull rule above

    url="$(git -C "$repo" remote get-url "$name" 2>/dev/null)" || continue
    host="$(remote_host "$url")"
    [[ "$host" == "github.com" ]] || continue
    github_remotes+=("$name")

    owner="$(remote_owner_segment "$url")"
    if github_owner && [[ "$owner" == "$GITHUB_OWNER" ]]; then
      github_owned+=("$name")
      REMOTE_PUSH+=("$name")
    fi
  done < <(git -C "$repo" remote 2>/dev/null)

  if (( ${#github_owned[@]} )); then
    REMOTE_BOOTSTRAP="${github_owned[0]}"
  elif (( ${#github_remotes[@]} )); then
    # No ownership signal (gh not authenticated) or none of the github.com
    # remotes are the user's own -- Scenario D (a clone of someone else's
    # public repo). Falling back to the first one found is still strictly
    # better than refusing to bootstrap at all.
    REMOTE_BOOTSTRAP="${github_remotes[0]}"
  fi
}

# Run directly (not sourced) to see the classification for one real repo,
# without wiring this into 42sync or any other script yet:
#   bash bin/42-internal/lib/42-remote-classify.sh /path/to/repo
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  repo="${1:-.}"
  git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || {
    echo "Not a git repo: $repo" >&2
    exit 1
  }
  classify_remotes "$repo"
  echo "repo:         $repo"
  echo "github owner: ${GITHUB_OWNER:-<could not determine -- gh missing or not authenticated>}"
  echo "all remotes:  ${REMOTE_NAMES[*]:-<none>}"
  echo "bootstrap:    ${REMOTE_BOOTSTRAP:-<none -- no github.com remote>}"
  echo "pull:         ${REMOTE_PULL[*]:-<none>}"
  echo "push:         ${REMOTE_PUSH[*]:-<none -- no github.com remote owned by \$GITHUB_OWNER>}"
fi
