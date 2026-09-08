#!/usr/bin/env bash
#
# set-email.sh -- personalize the contact address published on docs/'s
# GitHub Pages site (index.html, privacy.html, terms.html). Google requires
# a working contact address on these pages before it will publish an OAuth
# app out of "Testing" (see README, Configuration) -- anyone forking this
# repo for their own Google Cloud project needs their own address here, not
# the original author's.
#
# The address is stored REVERSED in each page (data-u/data-d attributes on
# a <span class="email">, decoded client-side by email.js) rather than
# plain text, so a scraper reading the raw HTML doesn't find a usable
# address -- same reasoning behind the <noscript> fallback spelling out
# "[at]"/"[dot]" instead of the literal characters. This script computes
# both obfuscated forms so nobody forking this repo has to hand-derive
# them.
#
# Usage:
#   ./set-email.sh you@example.com
#   ./set-email.sh                 # prompts interactively

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES=("$SRC/index.html" "$SRC/privacy.html" "$SRC/terms.html")

red()   { printf '\033[31m%s\033[0m\n' "$*" >&2; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
die()   { red "$*"; exit 1; }

email="${1:-}"
if [[ -z "$email" ]]; then
  read -r -p "Contact email to publish on the docs/ pages: " email
fi
[[ "$email" == *@*.* ]] || die "Not a valid-looking email: '$email' (expected something like you@example.com)"

local_part="${email%@*}"
domain="${email#*@}"

# Matches email.js's own rev(): reverse a string's characters. Prefers the
# standard `rev` utility (present on Linux, macOS, and Git-for-Windows'
# MSYS); falls back to a pure-bash loop for a minimal environment without
# it, the same "don't assume, degrade gracefully" style already used
# elsewhere in this toolkit's own install script.
reverse() {  # $1: string -> reversed string on stdout
  if command -v rev >/dev/null 2>&1; then
    printf '%s' "$1" | rev
    return
  fi
  local s="$1" out="" i
  for (( i = ${#s} - 1; i >= 0; i-- )); do out+="${s:$i:1}"; done
  printf '%s' "$out"
}

rev_local="$(reverse "$local_part")"
rev_domain="$(reverse "$domain")"

# The <noscript> fallback spells out "@" and "." as words for the same
# scraper-resistance reason the reversed data-u/data-d pair exists --
# matches this project's existing style exactly (see any of the three
# pages before this script touches them).
noscript_text="${local_part} [at] ${domain//./ [dot] }"

# No `sed -i`: BSD sed (macOS) and GNU sed (Linux, and Windows via Git
# Bash's MSYS coreutils) take incompatible arguments for it (BSD requires a
# backup-suffix argument, even if empty; GNU treats that same argument as
# the suffix to APPEND instead). Every other file edit in this toolkit
# writes to a temp file and moves it into place instead of relying on -i;
# this script does the same.
for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || die "Missing $f -- run this script from inside docs/, or leave it where it is and run it directly."
  tmp="$(mktemp)"
  sed -E \
    -e "s/data-u=\"[^\"]*\" data-d=\"[^\"]*\"/data-u=\"${rev_local}\" data-d=\"${rev_domain}\"/" \
    -e "s/<noscript>[^<]*<\/noscript>/<noscript>${noscript_text}<\/noscript>/" \
    "$f" > "$tmp"
  mv "$tmp" "$f"
  green "updated  $(basename "$f")"
done

echo
green "Done. Contact pages now publish: $email"
echo "Stored obfuscated in the HTML (email.js decodes it client-side) -- nothing in these files is plain-text."
