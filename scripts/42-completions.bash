# 42-completions.bash — bash tab-completion for 42sync/42links/42password/
# 42sync_install.sh/42projects. Sourced from ~/.bashrc by 42sync_install.sh,
# right after the PATH line.
#
# zsh is NOT covered -- it has its own, incompatible completion system
# (compdef/_arguments, not complete/compgen/COMPREPLY). A zsh equivalent
# would be a separate addition, not something this file can also do.
#
# Script-NAME completion (typing "42sy<TAB>" -> "42sync") needs nothing here:
# ~/bin is already on PATH, and bash's default completion already completes
# partial command names against everything on PATH. Only VERB completion
# (the second word) is built below.

_42_verb_complete() {
  # Only the verb (first argument) is completed -- these scripts don't need
  # ID/folder-argument completion today.
  (( COMP_CWORD == 1 )) || return 0
  local verbs
  verbs="$("${COMP_WORDS[0]}" __complete 2>/dev/null)"
  COMPREPLY=($(compgen -W "$verbs" -- "${COMP_WORDS[COMP_CWORD]}"))
}

complete -F _42_verb_complete 42sync 42links 42password 42sync_install.sh 42projects
