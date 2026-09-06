# Shared configuration for every 42* script -- A REPO FILE, NOT A PER-MACHINE
# ONE. This is the installed copy (~/bin/42-internal/lib/42-common.sh);
# 42sync_install.sh overwrites it from the repo's own
# bin/42-internal/lib/42-common.sh on every reinstall, same as it does
# 42sync/42links/etc. DO NOT HAND-EDIT THIS INSTALLED COPY -- the next
# `./42sync_install.sh apply` (run to pick up tool updates) silently reverts
# it.
#
# To change a default for every machine: edit THIS file in the repo itself,
# then reinstall. To change one on just THIS machine, in a way reinstalls
# never undo: run `42sync configure-set <name> <value>` (or
# `./42sync_install.sh configure-set ...` before ever installing), or
# hand-edit $CONFIG_PATH/42-common.local.sh directly -- see the bottom of
# this file for how that's wired in, bin/42-internal/lib/42-configure.sh for
# the configure-set/-reset/-show implementation, and README, Configuration ->
# Reconfiguring a single machine, for the full story.
#
# Each script sources this instead of keeping its own copy of these values,
# so there's one place (this file, or its machine-local override) to change
# the remote name, log retention, where things live, etc.
#
# Sourced via a $SCRIPT_DIR-relative path (see the sourcing line each
# script carries near its own top), so this works identically whether a
# script is run from its installed copy (~/bin/<name>, with this file at
# ~/bin/42-internal/lib/42-common.sh) or straight from a clone of the repo
# (bin/<name> in the repo, with this file at bin/42-internal/lib/42-common.sh)
# -- the repo's bin/ is deliberately laid out as a mirror of the installed
# ~/bin/, so the same relative path resolves correctly either way.
#
# Not every script uses every variable here -- that's fine, sourcing one
# unused assignment is harmless. A script's own genuinely-private variables
# (42links' BASE, 42password's SERVICE, etc.) stay defined locally in that
# script, not here -- this file is only for values more than one script
# needs to agree on.
#
# Every path-holding variable ends in _PATH, a rclone remote:path pair
# included -- HOME_PATH is the one root everything else is built from.

HOME_PATH="$HOME"

LOCAL_PATH="$HOME_PATH/Projects"
REMOTE_PATH="gdrive:_projects-sync-rclone"

# This toolkit's OWN config -- distinct from rclone's own $HOME_PATH/.config/rclone
# (rclone.conf, and the encrypted config password 42password manages), which
# stays exactly where rclone itself expects it, not something this toolkit
# controls or moves.
CONFIG_PATH="$HOME_PATH/.config/_projects-sync-rclone"
FILE_FILTERS="$CONFIG_PATH/filters/projects-filters.txt"
PROJECT_FILTERS="$CONFIG_PATH/filters/projects-local.txt"

STATE_PATH="$HOME_PATH/.local/state/_projects-sync-rclone"
LOG_PATH="$STATE_PATH/logs"
# bisync's listings live here, NOT in ~/.cache -- campus machines clear the
# cache between sessions, and losing the listings means a forced --resync
# every time. Derived from STATE_PATH rather than repeated separately.
WORK_PATH="$STATE_PATH/bisync"
KEEP_LOGS=20

BIN_PATH="$HOME_PATH/bin"

# HELPERS_DIR is wherever THIS file's own directory's parent landed -- a
# sibling-of-siblings anchor, so DEFAULTS_DIR/WIN_DIR/etc. below all resolve
# correctly in both layouts without any script needing to work it out
# independently: bin/42-internal in a repo clone (this file at
# bin/42-internal/lib/), ~/bin/42-internal once installed (this file at
# ~/bin/42-internal/lib/). ${BASH_SOURCE[0]} here refers to this file's own
# path, not whichever script sourced it. Everything under 42-internal/ is a
# dependency of the 42* commands, never one itself -- that's the whole
# reason bin/ has this one extra level of nesting.
HELPERS_DIR="$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"

# Where the default content for auto-created files lives: the
# projects-filters.txt/projects-local.txt content (nested under filters/,
# mirroring $CONFIG_PATH's own shape), READ-ME-FIRST.{txt,md} (42sync's
# seed/resync-apply drop both into $LOCAL_PATH if they aren't there yet --
# see seed_readme_first in 42sync), and 42-common.local.sh. All content a
# SCRIPT materializes into place, never edited in this directory itself.
DEFAULTS_DIR="$HELPERS_DIR/defaults"

# Windows-specific helper code that isn't plain data (unlike DEFAULTS_DIR's
# contents), so it gets its own directory rather than living in defaults/
# -- currently just the DPAPI password helper 42password copies from. See
# the longer comment in 42password for why it isn't in ~/bin itself either.
WIN_DIR="$HELPERS_DIR/win"

# Per-machine overrides for any variable set above. Never version-controlled
# and never overwritten by 42sync_install.sh once it exists -- same
# "materialize once from a template, then hands off for good" pattern as
# projects-filters.txt/projects-local.txt (see 42sync/42projects), just for
# these variables instead of bisync filters. Lives in $CONFIG_PATH, this
# toolkit's own config directory, not under ~/bin, specifically so it
# survives a `git pull` + reinstall of the tools themselves.
#
# Since every 42* script sources this file, this is the one place an
# override reaches all of them -- and because 42sync_install.sh sources
# this same file for its own BIN_PATH/LOG_PATH, creating this override file
# BEFORE the very first `./42sync_install.sh apply` (e.g. to install
# somewhere other than ~/bin) works too, not just after.
OVERRIDES_PATH="$CONFIG_PATH/42-common.local.sh"
mkdir -p "$(dirname "$OVERRIDES_PATH")"
[[ -f "$OVERRIDES_PATH" ]] || cp "$DEFAULTS_DIR/42-common.local.sh" "$OVERRIDES_PATH"
source "$OVERRIDES_PATH"
