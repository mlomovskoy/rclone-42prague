# Shared with 42password: knows how to read the rclone config password back
# out of this OS's secret store, so 42sync/42projects (anything that calls
# rclone directly) can export a known-fresh RCLONE_PASSWORD_COMMAND
# themselves -- rather than trusting whatever value happened to be
# inherited from the shell that launched them, which can go stale the
# moment CONFIG_PATH changes or the secret moves (see TROUBLESHOOTING.md,
# the stale-shell-env entry this exists to make impossible for every script
# in this toolkit -- it can still happen for a user's own ad-hoc
# `rclone ...` calls typed directly, which is what the shell rc line
# 42password writes is still for).
#
# Depends on CONFIG_PATH already being set (42-common.sh, sourced first).
# Storing the password itself (the interactive prompts, writing to the
# store) stays 42password's own job -- this file is read-only.

RCLONE_PW_SERVICE="rclone-config"

have() { command -v "$1" >/dev/null 2>&1; }

# Windows-native tools (powershell.exe) do not understand Git Bash's
# POSIX-style paths. cygpath ships with the same MSYS runtime Git Bash does,
# so it is safe to assume alongside it.
to_winpath() {
  if have cygpath; then cygpath -w "$1"; else printf '%s' "$1"; fi
}

case "$(uname -s)" in
  Darwin)                RCLONE_PW_OS=osx ;;
  Linux)                 RCLONE_PW_OS=linux ;;
  MINGW*|MSYS*|CYGWIN*)  RCLONE_PW_OS=windows ;;
  *)                     RCLONE_PW_OS="" ;;
esac

# Windows-only paths, derived from $CONFIG_PATH -- the one definition both
# 42password (which creates/writes them) and this file (which only ever
# reads them) share, so the two can never drift apart the way the old
# ~/.config/rclone hardcoding once did.
RCLONE_PW_WIN_HELPER="$CONFIG_PATH/rclone-password-helper.ps1"
RCLONE_PW_WIN_ENCFILE="$CONFIG_PATH/rclone-password.enc"

rclone_password_stored() {
  case "$RCLONE_PW_OS" in
    osx)     security find-generic-password -a "$USER" -s "$RCLONE_PW_SERVICE" -w >/dev/null 2>&1 ;;
    linux)   secret-tool lookup service "$RCLONE_PW_SERVICE" username "$USER" >/dev/null 2>&1 ;;
    windows) [[ -f "$RCLONE_PW_WIN_ENCFILE" ]] ;;
    *)       return 1 ;;
  esac
}

rclone_password_command() {
  case "$RCLONE_PW_OS" in
    osx)     printf 'security find-generic-password -a %s -s %s -w' "$USER" "$RCLONE_PW_SERVICE" ;;
    linux)   printf 'secret-tool lookup service %s username %s' "$RCLONE_PW_SERVICE" "$USER" ;;
    windows) printf 'powershell.exe -NoProfile -NonInteractive -File %s' "$(to_winpath "$RCLONE_PW_WIN_HELPER")" ;;
  esac
}

# Call once, near the top of any script about to invoke rclone. A no-op if
# 42password was never set up on this machine -- rclone then falls back to
# whatever it would otherwise do (an interactive prompt, RCLONE_CONFIG_PASS,
# an unencrypted config, or an inherited value from the caller's own shell
# that this has no business overriding when our own store has nothing in
# it).
export_rclone_password_command() {
  rclone_password_stored && export RCLONE_PASSWORD_COMMAND="$(rclone_password_command)"
  return 0
}
