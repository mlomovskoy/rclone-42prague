# Shared by 42sync_install.sh and 42password: which shell rc file to write
# setup lines into. Detection only -- what to do when the shell is
# something other than bash/zsh is each caller's own call (42sync_install.sh
# treats it as a skippable step, since PATH can still be set by hand;
# 42password can't proceed at all without a shell rc to write
# RCLONE_PASSWORD_COMMAND into), so this never dies or warns itself.
#
# Previously each script carried its own identical copy of this -- the
# exact kind of duplication that let 42password's own copy of the
# CONFIG_PATH path (fixed earlier) drift out of sync with the rest of the
# toolkit. Unified here so there's one place to fix if shell detection ever
# needs to change.

detect_shell_rc() {  # sets SHELL_NAME and SHELL_RC (SHELL_RC="" if unsupported)
  # Git for Windows' bash reports $SHELL as .../bash.exe, not bash -- strip
  # the extension so this matches the same way it does on Linux and macOS.
  SHELL_NAME="${SHELL##*/}"; SHELL_NAME="${SHELL_NAME%.exe}"
  case "$SHELL_NAME" in
    zsh)  SHELL_RC="$HOME/.zshrc" ;;
    bash) SHELL_RC="$HOME/.bashrc" ;;
    *)    SHELL_RC="" ;;
  esac
}
