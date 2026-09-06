#!/usr/bin/env bash
#
# 42sync_install.sh — put rclone and every 42* script in ~/bin. No root
# required. Runs on Linux, macOS, and Windows via Git for Windows' bash. Lives
# at the repo root (unlike the scripts it installs, which stay in bin/
# and get copied into ~/bin) precisely so it's the first thing visible from a
# fresh clone. Run with no arguments to see every verb this script accepts.
#
# Campus machines give you no admin rights, so rclone is installed as a plain
# binary in ~/bin rather than through a package manager. Everything here is
# idempotent: re-running is safe, and is the intended way to update.
#
# Pin a version instead of taking whatever is current:
#   INSTALL_RCLONE_VERSION=1.75.0 ./42sync_install.sh apply
#
# Deliberately not named RCLONE_VERSION: rclone reads every RCLONE_<FLAG>
# variable in the environment as --<flag>, so RCLONE_VERSION=1.75.0 becomes
# --version=1.75.0 on every rclone call — an invalid boolean, which makes even
# `rclone version` fail.
#
# The rclone download is checked against a SHA256 that is itself PGP-verified
# against rclone's release signing key (rclone-release-key.asc, repo root).
# This is required: if the signature cannot be checked, nothing is installed. To
# install on a machine without gpg, opt out explicitly with
# INSTALL_ALLOW_UNSIGNED=1 — that falls back to the SHA256 alone.
#
# This installs tools. It does NOT configure the remote or move any data —
# `rclone config` and `42sync seed` stay manual because both need decisions
# only you can make. The summary at the end says which are still outstanding.

set -euo pipefail

BASE_URL="https://downloads.rclone.org"
# Directly-runnable commands only -- everything else lives under
# bin/42-internal/ instead (installed via the loop below), distinguishing what
# you actually run from what those commands merely depend on.
SCRIPTS=(42sync 42links 42password 42projects 42logs)

# rclone's release signing key. Cross-checked 2026-08-26 against rclone.org's
# release_signing page, the same page's source in the rclone git repo, and
# keys.openpgp.org — all three publish this fingerprint. Re-check it yourself
# before trusting it; that is the whole point of a pinned fingerprint.
RCLONE_KEY_FPR="FBF737ECE9F8AB18604BD2AC93935E02FF3B54FA"

# This file's own directory, so the installer works from a clone in any path.
# The installer itself lives at the repo root, alongside the signing key --
# the key is only ever read here, during this script's own rclone-download
# check, and never copied into ~/bin, so it doesn't belong under bin/ with
# everything that IS installed there. 42sync/42links/42password and the
# shared lib do live in bin/ -- computed before sourcing the shared lib
# below, since that lookup needs $REPO_BINDIR too.
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_BINDIR="$SRC/bin"
RCLONE_KEY_FILE="$SRC/rclone-release-key.asc"

# Colour only on a terminal; the log gets plain text either way.
if [[ -t 1 ]]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_OFF=$'\033[0m'
else
  C_RED=""; C_GRN=""; C_YEL=""; C_OFF=""
fi

# Logging must never be the thing that breaks an install. Guarded on $LOG
# being set: an unknown-verb die() fires before $LOG exists (it's named
# after the verb, so it can't be assigned until the verb is validated), and
# under `set -u` an unguarded reference there would replace the intended
# "Unknown verb" message with an unbound-variable error instead.
logmsg() { [[ -n "${LOG:-}" ]] || return 0; printf '%s\n' "$*" >> "$LOG" 2>/dev/null || true; }

say()    { printf '%s\n' "$*";                       logmsg "$*"; }
red()    { printf '%s%s%s\n' "$C_RED" "$*" "$C_OFF"; logmsg "$*"; }
green()  { printf '%s%s%s\n' "$C_GRN" "$*" "$C_OFF"; logmsg "$*"; }
yellow() { printf '%s%s%s\n' "$C_YEL" "$*" "$C_OFF"; logmsg "$*"; }
die()    { red "$*" >&2; logmsg "RESULT: failed"; exit 1; }

prune_logs() {
  local keep
  keep=$(ls -1t "$LOG_PATH"/42sync_install-{apply,check,reinstall}-*.log 2>/dev/null) || true
  [[ -n "$keep" ]] || return 0
  printf '%s\n' "$keep" | tail -n +$((KEEP_LOGS+1)) | xargs -r rm --
}

VERBS=(apply check reinstall configure-set configure-reset configure-show)

print_verbs() {
  cat <<'EOF'
42sync_install.sh <verb>

  apply       install or update whatever needs it
  check       dry run: show what would happen, change nothing
  reinstall   reinstall rclone even when the wanted version is already there

  configure-set <name> <value>  set a per-machine override, e.g.:
                                   ./42sync_install.sh configure-set bin-path /opt/mybin
  configure-reset <name>         revert that override to its default
  configure-show                 print the current effective value of every setting
EOF
}

if [[ $# -eq 0 ]]; then
  print_verbs
  exit 0
fi

MODE="$1"

if [[ "$MODE" == __complete ]]; then
  printf '%s\n' "${VERBS[@]}"
  exit 0
fi

# BIN_PATH, LOG_PATH, KEEP_LOGS come from here -- shared with every other 42*
# script. This installer is the one exception that can't use a plain
# $SCRIPT_DIR-relative sourcing line for it (it lives at the repo root, not
# alongside the scripts it installs), so it goes through $REPO_BINDIR instead.
# Sourced only now, after the no-args/__complete checks above: this file has
# a side effect (creating $CONFIG_PATH/42-common.local.sh if missing), and a
# purely informational query must never trigger it. Confirmed empirically:
# it used to.
source "$REPO_BINDIR/42-internal/lib/42-common.sh"

# configure_set/configure_reset/configure_show -- the configure-* verbs below
# just call these. See that file for what they touch and why.
source "$REPO_BINDIR/42-internal/lib/42-configure.sh"

# ensure_line() -- setup_shell() below uses this to write the PATH and
# tab-completion lines. Shared with 42password, which uses it for
# RCLONE_PASSWORD_COMMAND -- same "replace the old value instead of
# appending a second one alongside it" fix applies to both.
source "$REPO_BINDIR/42-internal/lib/42-ensure-line.sh"

# Same directory every 42* script logs to, so there is one place to look.
# Prefixed with this script's own name (".sh" stripped) so logs stay
# identifiable even though "apply"/"check" are shared verb names with other
# scripts in the same $LOG_PATH.
mkdir -p "$LOG_PATH"

# A different kind of action entirely (editing a config file, not installing
# anything) -- handled here and exited before any install-specific setup
# (the per-run log file below, rclone/script installation) runs at all.
case "$MODE" in
  configure-set)
    [[ $# -eq 3 ]] || die "Usage: ./42sync_install.sh configure-set <name> <value>"
    configure_set "$2" "$3"
    exit 0
    ;;
  configure-reset)
    [[ $# -eq 2 ]] || die "Usage: ./42sync_install.sh configure-reset <name>"
    configure_reset "$2"
    exit 0
    ;;
  configure-show)
    configure_show
    exit 0
    ;;
esac

DRY=0
FORCE=0
case "$MODE" in
  apply)     ;;
  check)     DRY=1 ;;
  reinstall) FORCE=1 ;;
  *)         die "Unknown verb '$MODE'. Run './42sync_install.sh' with no arguments to see the list." ;;
esac

LOG="$LOG_PATH/42sync_install-$MODE-$(date +%Y-%m-%d-%H%M%S).log"
: > "$LOG"
ln -sfn "$LOG" "$LOG_PATH/42sync_install-$MODE-last.log"

TODO=()          # things left for the user, printed at the end
note_todo() { TODO+=("$1"); }

TMP=""
cleanup() { [[ -n "$TMP" && -d "$TMP" ]] && rm -rf "$TMP"; return 0; }
# Print the log path on EVERY exit path, not just the successful one — a failed
# install is exactly when you want to know where the evidence went.
on_exit() { cleanup; prune_logs; printf '%sLog: %s%s\n' "$C_GRN" "$LOG" "$C_OFF"; }
trap on_exit EXIT

# ---------------------------------------------------------------- platform ---

# EXE is the binary suffix ("" everywhere except Windows). Windows here means
# Git for Windows' bash (MSYS/MINGW), not native cmd/PowerShell — this script
# is bash, so that is the only way it runs there at all. uname -s reports
# something like MINGW64_NT-10.0-... or MSYS_NT-... in that environment.
EXE=""
case "$(uname -s)" in
  Linux)                 OS=linux ;;
  Darwin)                OS=osx ;;
  MINGW*|MSYS*|CYGWIN*)  OS=windows; EXE=".exe" ;;
  *)      die "Unsupported OS: $(uname -s). This installer covers Linux, macOS, and
Windows via Git for Windows' bash (not native cmd/PowerShell)." ;;
esac

case "$(uname -m)" in
  x86_64|amd64)  ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *)             die "Unsupported architecture: $(uname -m)." ;;
esac

# ----------------------------------------------------------------- helpers ---

have() { command -v "$1" >/dev/null 2>&1; }

fetch() {  # url dest
  logmsg "fetch: $1"
  if   have curl; then curl -fsSL --retry 3 --max-time 300 -o "$2" "$1" 2>>"$LOG"
  elif have wget; then wget -q -O "$2" "$1" 2>>"$LOG"
  else die "Need curl or wget to download rclone."
  fi
}

# Windows-native tools (certutil, powershell) do not understand Git Bash's
# POSIX-style paths. cygpath is part of the same MSYS runtime Git Bash ships,
# so it is the one thing here safe to assume alongside it.
to_winpath() {
  if have cygpath; then cygpath -w "$1"; else printf '%s' "$1"; fi
}

sha256_of() {
  if   have sha256sum; then sha256sum "$1" | awk '{print $1}'
  elif have shasum;    then shasum -a 256 "$1" | awk '{print $1}'
  elif have certutil.exe; then
    # Git Bash ships neither sha256sum nor shasum on some minimal installs;
    # certutil is a native Windows tool, present even then.
    certutil.exe -hashfile "$(to_winpath "$1")" SHA256 | sed -n '2p' | tr -d ' \r'
  else die "Need sha256sum, shasum, or certutil to verify the download."
  fi
}

# `install` (the coreutil) is not guaranteed on a minimal Git Bash — fall back
# to cp+chmod, which is what it does under the hood anyway for our purposes.
install_file() {  # src dest
  if have install; then
    install -m 755 "$1" "$2"
  else
    cp -f "$1" "$2" && chmod 755 "$2" 2>/dev/null
  fi
}

# Git Bash does not bundle unzip by default. PowerShell's Expand-Archive is
# present on every Windows 10+ box, so fall back to calling it directly rather
# than asking the user to separately install an unzip binary.
unzip_archive() {  # zip destdir
  if have unzip; then
    unzip -q -o "$1" -d "$2"
    return $?
  fi
  if have powershell.exe; then
    mkdir -p "$2"
    powershell.exe -NoProfile -NonInteractive -Command \
      "Expand-Archive -LiteralPath '$(to_winpath "$1")' -DestinationPath '$(to_winpath "$2")' -Force" \
      >>"$LOG" 2>&1
    return $?
  fi
  die "Need unzip (or, on Windows, PowerShell's Expand-Archive) to unpack rclone."
}

# Look in $BIN_PATH before consulting PATH: on a fresh machine ~/bin is not on PATH
# yet (this script is what puts it there), so trusting `command -v` alone would
# miss an rclone we installed a moment ago and re-download it on every run.
# Sets RCLONE_PATH and RCLONE_VER. Deliberately not a value-returning function:
# called in a command substitution it would set those in a subshell, and the
# caller would see them empty.
RCLONE_PATH=""
RCLONE_VER=""
detect_rclone() {
  RCLONE_PATH=""; RCLONE_VER=""
  if   [[ -x "$BIN_PATH/rclone$EXE" ]]; then RCLONE_PATH="$BIN_PATH/rclone$EXE"
  elif have rclone;                   then RCLONE_PATH="$(command -v rclone)"
  else return 0
  fi
  # `rclone version` does not read the config file, so this never prompts for
  # the config password even when the config is encrypted.
  RCLONE_VER="$("$RCLONE_PATH" version 2>/dev/null | head -1 | awk '{print $2}' | sed 's/^v//' || true)"
  if [[ -z "$RCLONE_VER" ]]; then
    yellow "warn       found $RCLONE_PATH but could not read its version"
    say   "           A stray RCLONE_* variable in your environment will do this:"
    say   "           rclone reads RCLONE_<FLAG> as --<flag>. Check with: env | grep ^RCLONE_"
  fi
}

# Sets EXPECTED_SHA to the signed checksum for $2, or dies.
#
# Not a value-returning function on purpose: `die` inside a command substitution
# would only exit the subshell, and the caller would sail on with an empty
# checksum — which is precisely the failure this whole function exists to stop.
EXPECTED_SHA=""
verify_sums() {  # sumsfile asset
  local sums="$1" asset="$2" gnupg fpr payload

  EXPECTED_SHA=""

  if ! have gpg || [[ ! -f "$RCLONE_KEY_FILE" ]]; then
    local why="gpg is not installed"
    [[ -f "$RCLONE_KEY_FILE" ]] || why="$RCLONE_KEY_FILE is missing"

    # Verified by default. Skipping is a decision with a real consequence, so it
    # has to be made deliberately rather than fallen into by running on a machine
    # that happens to lack gpg.
    if [[ "${INSTALL_ALLOW_UNSIGNED:-0}" != "1" ]]; then
      die "Cannot verify rclone's signature: $why.

Refusing to install a binary that has not been verified.

  gpg missing        Most Linux and macOS installs have it. Campus machines give
                     you no admin rights, so if it is genuinely absent you cannot
                     simply install it — use a machine that has it, or opt out.
  key file missing   Restore it:  git checkout rclone-release-key.asc

To install anyway, accepting that only the SHA256 is checked — which catches a
corrupted download but not a tampered mirror:

  INSTALL_ALLOW_UNSIGNED=1 ./42sync_install.sh"
    fi
    yellow "  warn: signature NOT checked ($why), INSTALL_ALLOW_UNSIGNED=1 is set"
    say   "        The SHA256 still catches a corrupted download, but it comes from"
    say   "        the same server as the zip — it cannot catch a tampered mirror."
    EXPECTED_SHA="$(awk -v a="$asset" '''$2 == a {print $1; exit}''' "$sums")"
    [[ -n "$EXPECTED_SHA" ]] || die "No checksum for $asset in SHA256SUMS — wrong version or platform?"
    return 0
  fi

  # A private keyring in the temp dir. Importing into the user'''s ~/.gnupg would be
  # a side effect they never asked for, and it would outlive this script.
  #
  # mkdir and chmod are separate here (rather than `mkdir -m 700`): on Windows/MSYS
  # the directory is created under an NTFS ACL that already restricts it to the
  # current user, but the chmod step itself can still fail there with "Permission
  # denied" even though the mkdir succeeded — and `set -e` would then abort the
  # whole install over a permission bit that was never the real security boundary
  # on that filesystem.
  gnupg="$TMP/gnupg"
  rm -rf "$gnupg"; mkdir -p "$gnupg"; chmod 700 "$gnupg" 2>/dev/null || true
  gpg --batch --quiet --homedir "$gnupg" --import "$RCLONE_KEY_FILE" 2>>"$LOG" \
    || die "Could not import $RCLONE_KEY_FILE — is it a valid public key?"

  # Trust the pinned fingerprint, not the file: confirm the bundled key is the
  # key we think it is before letting it vouch for anything.
  fpr="$(gpg --batch --homedir "$gnupg" --with-colons --fingerprint 2>/dev/null \
         | awk -F: '''/^fpr:/{print $10; exit}''')"
  [[ "$fpr" == "$RCLONE_KEY_FPR" ]] || die "Bundled signing key is $fpr,
but this script pins $RCLONE_KEY_FPR. Refusing to install."

  # `gpg --verify` exits 0 for a good signature from ANY key in the keyring, so
  # the exit status alone proves nothing. Assert who signed it.
  gpg --batch --quiet --homedir "$gnupg" --status-fd 3 \
      --verify "$sums" 3>"$TMP/gpgstatus" 2>>"$LOG" || true
  if ! grep -q "^\[GNUPG:\] VALIDSIG $RCLONE_KEY_FPR " "$TMP/gpgstatus"; then
    # $TMP is wiped on exit, so copy the evidence somewhere that outlives it.
    logmsg "--- gpg status output ---"
    cat "$TMP/gpgstatus" >> "$LOG" 2>/dev/null || true
    logmsg "--- SHA256SUMS as received (first 40 lines) ---"
    head -40 "$sums" >> "$LOG" 2>/dev/null || true
    logmsg "--- end evidence ---"
    die "SHA256SUMS is not validly signed by $RCLONE_KEY_FPR.
Refusing to install. This is what a tampered or truncated sums file looks like.
The signature output and the file as received were kept in:
  $LOG"
  fi

  # Read the checksum from gpg'''s output rather than the file. In a clearsigned
  # file the signature covers only the payload, so unsigned text can sit outside
  # it — verifying the file and then grepping the file is a classic way to be
  # fooled by a line the signature never covered.
  payload="$(gpg --batch --quiet --homedir "$gnupg" --decrypt "$sums" 2>/dev/null)"
  EXPECTED_SHA="$(awk -v a="$asset" '''$2 == a {print $1; exit}''' <<<"$payload")"
  [[ -n "$EXPECTED_SHA" ]] || die "No checksum for $asset in the signed SHA256SUMS — wrong version or platform?"
  say "  signature ok (signed by $RCLONE_KEY_FPR)"
}

# ------------------------------------------------------------------ rclone ---

install_rclone() {
  local want installed asset url expected actual

  want="${INSTALL_RCLONE_VERSION:-}"
  if [[ -z "$want" ]]; then
    TMP="${TMP:-$(mktemp -d)}"
    fetch "$BASE_URL/version.txt" "$TMP/version.txt" \
      || die "Could not reach $BASE_URL — check the network, or pin INSTALL_RCLONE_VERSION."
    # version.txt reads: "rclone v1.75.0"
    want="$(awk '{print $2}' "$TMP/version.txt" | sed 's/^v//')"
  fi
  [[ -n "$want" ]] || die "Could not determine which rclone version to install."

  detect_rclone
  installed="$RCLONE_VER"

  if [[ -n "$installed" ]] && (( ! FORCE )); then
    if [[ "$installed" == "$want" ]]; then
      green "ok         rclone v$installed already installed ($RCLONE_PATH)"
      return 0
    fi
    yellow "update     rclone v$installed -> v$want"
  elif [[ -n "$installed" ]]; then
    yellow "reinstall  rclone v$installed -> v$want (force)"
  else
    yellow "install    rclone v$want"
  fi

  if (( DRY )); then
    say "  would download $BASE_URL/v$want/rclone-v$want-$OS-$ARCH.zip and install it"
    say "  to ${BIN_PATH/#$HOME/\~}/rclone$EXE after checking its SHA256"
    if have gpg && [[ -f "$RCLONE_KEY_FILE" ]]; then
      say "  against a SHA256SUMS verified as signed by $RCLONE_KEY_FPR"
    elif [[ "${INSTALL_ALLOW_UNSIGNED:-0}" == "1" ]]; then
      yellow "  WITHOUT a signature check — no gpg or no key file, and"
      yellow "  INSTALL_ALLOW_UNSIGNED=1 is set"
    else
      red    "  it would REFUSE: no gpg or no key file, so the signature cannot be"
      red    "  checked. See INSTALL_ALLOW_UNSIGNED in the header comment."
    fi
    return 0
  fi

  TMP="${TMP:-$(mktemp -d)}"
  asset="rclone-v$want-$OS-$ARCH.zip"
  url="$BASE_URL/v$want/$asset"

  say "  downloading $asset"
  fetch "$url" "$TMP/$asset" || die "Download failed: $url"
  fetch "$BASE_URL/v$want/SHA256SUMS" "$TMP/SHA256SUMS" \
    || die "Could not fetch SHA256SUMS for v$want — refusing to install unverified."

  verify_sums "$TMP/SHA256SUMS" "$asset"
  expected="$EXPECTED_SHA"

  actual="$(sha256_of "$TMP/$asset")"
  if [[ "$actual" != "$expected" ]]; then
    logmsg "checksum expected=$expected actual=$actual asset=$asset"
    die "Checksum mismatch for $asset.
  expected $expected
  got      $actual
Nothing was installed. Delete any partial download and try again."
  fi
  say "  checksum ok"

  unzip_archive "$TMP/$asset" "$TMP/x" || die "Failed to unpack $asset."
  [[ -f "$TMP/x/rclone-v$want-$OS-$ARCH/rclone$EXE" ]] \
    || die "Archive did not contain the expected rclone binary."

  mkdir -p "$BIN_PATH"
  # install_file replaces the file rather than writing through it, so this is
  # safe even if another shell is running the old binary right now.
  install_file "$TMP/x/rclone-v$want-$OS-$ARCH/rclone$EXE" "$BIN_PATH/rclone$EXE"
  green "installed  rclone v$want -> ${BIN_PATH/#$HOME/\~}/rclone$EXE"
}

# ----------------------------------------------------------------- scripts ---

# Installs one file at a $BIN_PATH-relative subpath (e.g.
# "42-internal/lib/42-common.sh", "42-internal/defaults/projects-filters.txt"),
# creating whatever subdirectory it needs. Shared by install_scripts() below
# for everything that isn't a flat top-level script -- the lib every script
# sources, and the on-disk defaults auto-created files get copied from.
install_aux_file() {  # rel-path (relative to both $REPO_BINDIR and $BIN_PATH)
  local rel="$1" src="$REPO_BINDIR/$1" dst="$BIN_PATH/$1"
  [[ -f "$src" ]] || die "Missing $src — run this from a clone of the repo."
  if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
    green "ok         $rel already current in ${BIN_PATH/#$HOME/\~}"
  elif (( DRY )); then
    if [[ -f "$dst" ]]; then
      yellow "would update  $rel in ${BIN_PATH/#$HOME/\~}"
    else
      yellow "would install $rel to ${BIN_PATH/#$HOME/\~}"
    fi
  else
    mkdir -p "$(dirname "$dst")"
    install_file "$src" "$dst"
    green "installed  $rel -> ${BIN_PATH/#$HOME/\~}/$rel"
  fi
}

install_scripts() {
  local name

  # Everything nested under bin/ (bin/42-internal/lib/, bin/42-internal/defaults/,
  # bin/42-internal/win/, and whatever gets added later) is installed first, and
  # separately from the flat SCRIPTS loop below, mirroring the repo's own
  # layout under ~/bin rather than flattening everything. bin/'s only
  # top-level members are the flat 42* commands (handled by the SCRIPTS loop)
  # -- everything a command depends on but that isn't itself directly
  # runnable lives one level down, under 42-internal/, distinguishing the two:
  # 42-internal/lib/ is sourced rather than run directly (42-common.sh, every
  # script's shared config; 42-configure.sh, the configure-set/-reset/-show
  # implementation; 42-completions.bash, sourced by the user's own shell rc);
  # 42-internal/defaults/ is on-disk default content scripts copy from
  # (projects-filters.txt/projects-local.txt, READ-ME-FIRST.{txt,md},
  # 42-common.local.sh -- see the longer comment in 42-common.sh);
  # 42-internal/win/ is Windows-specific helper code that isn't plain data, so it
  # doesn't belong in defaults/ either (see 42password). Walked by `find`
  # rather than one hardcoded loop per name or nesting depth, so a new
  # subdirectory -- at any depth -- needs no change here.
  local aux rel
  while IFS= read -r -d '' aux; do
    rel="${aux#"$REPO_BINDIR"/}"
    install_aux_file "$rel"
  done < <(find "$REPO_BINDIR" -mindepth 2 -type f -print0)

  for name in "${SCRIPTS[@]}"; do
    [[ -f "$REPO_BINDIR/$name" ]] || die "Missing $REPO_BINDIR/$name — run this from a clone of the repo."

    if [[ -f "$BIN_PATH/$name" ]] && cmp -s "$REPO_BINDIR/$name" "$BIN_PATH/$name"; then
      green "ok         $name already current in ${BIN_PATH/#$HOME/\~}"
      continue
    fi
    if (( DRY )); then
      if [[ -f "$BIN_PATH/$name" ]]; then
        yellow "would update  $name in ${BIN_PATH/#$HOME/\~}"
      else
        yellow "would install $name to ${BIN_PATH/#$HOME/\~}"
      fi
      continue
    fi
    mkdir -p "$BIN_PATH"
    install_file "$REPO_BINDIR/$name" "$BIN_PATH/$name"
    green "installed  $name -> ${BIN_PATH/#$HOME/\~}/$name"
  done
}

# ---------------------------------------------------------------- shell rc ---

setup_shell() {
  local rc shellname
  # Git for Windows' bash reports $SHELL as .../bash.exe, not bash — strip the
  # extension so this matches the same way it does on Linux and macOS.
  shellname="${SHELL##*/}"; shellname="${shellname%.exe}"
  case "$shellname" in
    zsh)  rc="$HOME/.zshrc" ;;
    bash) rc="$HOME/.bashrc" ;;
    *)    yellow "skip       unknown shell '$shellname' — add $BIN_PATH to PATH yourself"
          return 0 ;;
  esac
  [[ -f "$rc" ]] || { (( DRY )) || : > "$rc"; }

  # Write $HOME symbolically when BIN_PATH is still the plain default (portable
  # across a future $HOME change, e.g. an account rename) -- but a BIN_PATH
  # override only helps if the line landing in the user's shell rc points at
  # that same real location, so fall back to the literal resolved value
  # whenever it's been overridden to anything else. $PATH itself stays
  # escaped either way, so it expands at shell-startup time, not now.
  local bin_path_rc="$BIN_PATH"
  [[ "$BIN_PATH" == "$HOME/bin" ]] && bin_path_rc='$HOME/bin'
  # Patterns match ANY line this toolkit would ever write for that one
  # setting, whatever bin-path it names -- so a bin-path change replaces
  # the old line instead of leaving it behind alongside a new one.
  ensure_line "$rc" '^export PATH="[^"]*:\$PATH"$' \
    "export PATH=\"$bin_path_rc:\$PATH\"" "PATH entry for ${BIN_PATH/#$HOME/\~}"

  # Tab-completion for every 42* script's verbs. bash only -- zsh has its own,
  # incompatible completion system (compdef/_arguments, not
  # complete/compgen/COMPREPLY), so this line would be silently inert there
  # even if added; skip it rather than write a line that does nothing.
  if [[ "$shellname" == bash ]]; then
    ensure_line "$rc" '^source ".*/42-internal/lib/42-completions\.bash"$' \
      "source \"$bin_path_rc/42-internal/lib/42-completions.bash\"" 'tab-completion for 42* scripts'
  fi

  # zsh does not treat '#' as a comment interactively, so pasted commands with
  # trailing comments arrive as arguments. This has caused real confusion here.
  # Never changes, so the match pattern is just the line itself.
  if [[ "$shellname" == zsh ]]; then
    ensure_line "$rc" '^setopt interactive_comments$' 'setopt interactive_comments' 'interactive_comments'
  fi

  case ":$PATH:" in
    *":$BIN_PATH:"*) ;;
    *) note_todo "Open a new shell, or run: export PATH=\"$BIN_PATH:\$PATH\"" ;;
  esac
}

# ------------------------------------------------------------------- checks ---

post_checks() {
  local conf rclone_bin perms

  # Ask rclone itself where its config lives rather than hardcoding the
  # XDG-style ~/.config/rclone/rclone.conf path: native Windows builds default
  # to %APPDATA%\rclone\rclone.conf instead, and hardcoding the Linux path
  # there means this check always reports "no config" even after one exists.
  if [[ -x "$BIN_PATH/rclone$EXE" ]]; then rclone_bin="$BIN_PATH/rclone$EXE"
  elif have rclone;                   then rclone_bin="$(command -v rclone)"
  else rclone_bin=""
  fi
  conf=""
  [[ -n "$rclone_bin" ]] && conf="$("$rclone_bin" config file 2>/dev/null | tail -1 | tr -d '\r')"
  [[ -n "$conf" ]] || conf="$HOME/.config/rclone/rclone.conf"

  if [[ -f "$conf" ]]; then
    green "ok         rclone config exists"
    if have stat; then
      perms="$(stat -c '%a' "$conf" 2>/dev/null || stat -f '%Lp' "$conf" 2>/dev/null || echo '')"
      if [[ -n "$perms" && "$perms" != "600" ]]; then
        yellow "warn       $conf is mode $perms, not 600"
        note_todo "Tighten the config: chmod 600 $conf"
      fi
    fi
  else
    yellow "todo       no rclone config yet"
    note_todo "Configure the remote: rclone config   (see README, Configuration)"
    note_todo "Then encrypt it: rclone config -> s) Set configuration password"
  fi

  if [[ ! -d "$LOCAL_PATH" ]]; then
    note_todo "$LOCAL_PATH is missing — if that is expected: 42sync seed"
  elif [[ ! -f "$LOCAL_PATH/RCLONE_TEST" ]]; then
    yellow "warn       $LOCAL_PATH exists but has no RCLONE_TEST marker"
    note_todo "$LOCAL_PATH has no access marker — read README, Safety mechanisms, before syncing"
  else
    green "ok         $LOCAL_PATH present with its access marker"
    note_todo "Create the shortcuts if you have not on this machine: 42links"
  fi
}

# --------------------------------------------------------------------- main ---

logmsg "=== 42sync_install.sh $(date '+%F %T') mode=$MODE host=$(uname -n) ==="
logmsg "target=$OS-$ARCH bindir=$BIN_PATH src=$SRC"

if (( DRY )); then
  yellow "Dry run — nothing will be changed."
  echo
fi
say "Target: $OS-$ARCH, installing into ${BIN_PATH/#$HOME/\~}"
echo

install_rclone
install_scripts
setup_shell
post_checks

echo
if (( DRY )); then
  yellow "Dry run — nothing was changed."
else
  green "Done."
fi

if (( ${#TODO[@]} )); then
  echo
  say "Still to do on this machine:"
  printf '  - %s\n' "${TODO[@]}"
  printf '  - %s\n' "${TODO[@]}" >> "$LOG" 2>/dev/null || true
fi

logmsg "RESULT: ok"
