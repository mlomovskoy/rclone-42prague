# Changelog

Notable changes, newest first. Commit hashes are short and stable within this repo.

## 1.2.0 -- Rename-aware sync, hardened filters, bash 3.2 (2026-11-23)

- **A plain folder rename no longer trips the delete guard.** `--track-renames`
  (already present) turns a rename of unchanged files into a server-side move on
  Drive; the new `--max-delete-renames-aware` stops the guard counting those
  moves as deletions. Checked on rclone 1.76 with a 12-of-13-file rename (aborted
  without the flag, moved cleanly with it) and a genuine mass delete (still
  stopped, data kept). A rename that also edits the files, or a machine whose
  baseline predates a rename made elsewhere, still needs `force-check`/`force-apply`.
  The guard's message now says so.
- **Per-repo exclusion remembered.** Every repo path that ever had an onboarding
  marker is recorded, so a renamed or deleted onboarded repo's old `.git` on
  Drive stays excluded instead of being pulled back down. Per-repo
  `.git/info/exclude` carve-out rules are emitted ahead of the global one.
- **Empty folders sync** (`--create-empty-src-dirs`), so a renamed or deleted
  folder no longer leaves an empty shell on the other side.
- **Skipped (dirty) repos are frozen in bisync's baseline** across a skipped run,
  so the next run does not turn them into `.conflict` files. Falls back with a
  warning if the listing format is not recognised.
- `42sync` warns about folders bisync reported removed that Drive refused to
  delete (their trash holds items this app cannot touch).
- `reconstitute` checks that a repo's `.git` is a valid repository, not just that
  it exists, and moves a broken skeleton aside.
- macOS bash 3.2 compatibility: no `mapfile`, safe empty-array expansion under
  `set -u`.

## 1.1.0 -- Machine heartbeat and notices (2026-11-22)

Releases before this one predate version numbers and are understood as 1.0.0.
The repo-root `VERSION` file is now the source of truth for the number;
bump it in the same commit as the change it describes (minor for features,
patch for fixes).

- **`42sync status --all`**: every machine that has run this version, with its
  tool version, last run and result, last successful sync, and whether its
  folder layout matches this one. Flags `outdated` installs and `STALE`
  machines (nothing heard for 14 days).
- **Heartbeat on every Drive-touching verb**, including failed and
  guard-aborted runs. Published to `gdrive:_projects-sync-rclone.meta` -- a
  sibling of the synced folder, so older installs and bisync never see it.
  A failure to publish or read never changes the verb's own exit status.
- **Notices between machines**: `42sync note "text"`, plus automatic
  `layout-changed`, `tool-upgraded` and `guard-aborted` notices. Displayed
  once on the receiving machine, which writes an acknowledgement. Never
  executed; control characters are stripped before printing.
- **Version stamp**: `42sync_install.sh` writes tool version, source commit
  (with `+dirty` for uncommitted trees) and protocol number to
  `~/bin/42-internal/VERSION`.
- New settings: `meta-enabled`, `machine-label` (`42sync configure-set`).
- A machine that hasn't been upgraded does not report; it appears only after
  one manual `git pull && ./42sync_install.sh apply`.

## Restructuring, per-machine config, and hardening (2026-09-06)

### Structure

- **`scripts/` renamed to `bin/`, mirroring what gets installed to `~/bin`.**
  Everything a command depends on but that isn't itself directly runnable —
  shared lib code, on-disk default content, Windows-only helper files — now
  lives one level down, under `bin/42-internal/`, instead of sitting flat
  alongside the runnable commands. (`7567d10`)
- Shared config variables renamed to a consistent `_PATH` convention
  (`LOCAL_PATH`, `REMOTE_PATH`, `CONFIG_PATH`, `STATE_PATH`, `LOG_PATH`,
  `WORK_PATH`, `BIN_PATH`). (`7567d10`)
- New remote path: `gdrive:_projects-sync-rclone` (previously a different
  name). Existing machines need `42sync resync-check` /
  `resync-apply` once against the new path — there is no baseline for it yet
  even if one existed for the old name. (`7567d10`)

### Per-machine configuration overrides

- Added `configure-set` / `configure-reset` / `configure-show`, on both
  `42sync_install.sh` (works even before the first install) and every
  installed `42*` script. Lets one machine override any setting (`local-path`,
  `bin-path`, `keep-logs`, etc.) without editing the repo, via
  `~/.config/_projects-sync-rclone/42-common.local.sh` — created once,
  commented out, and never touched again by the installer. See README,
  *Reconfiguring a single machine*. (`7567d10`)

### `42projects`: default flipped to opt-in

- **Breaking, deliberate:** a fresh machine, or a project new to Drive this
  machine has never seen, now starts **excluded** — nothing pulls down until
  you explicitly `42projects include <ID>`. Previously the default was
  opt-out. (`280594c`)
- `42projects` now logs failures through the same `logmsg()` path every other
  script uses (a `die()` used to print to the terminal only, never reaching
  any log file), and refuses with a clear message instead of silently
  treating a failed `rclone lsd` as "Drive is empty" — that used to show
  every local project as excluded/local-only with no indication anything had
  gone wrong. (`db9509a`)
- `42projects list`'s hint block was missing the `delete-apply` line entirely
  — added. (`4c35848`)

### Password command no longer trusts the inherited shell

- **Root cause fixed:** `42sync`, `42projects`, and `42password` now compute
  `RCLONE_PASSWORD_COMMAND` fresh from the current config on every
  invocation (`bin/42-internal/lib/42-password-command.sh`), instead of
  relying on whatever the shell happened to have exported at startup. A
  `~/.bashrc` edit (e.g. after `42password reinstall` moves where the helper
  lives) used to require sourcing it or opening a new shell before any `42*`
  command would pick it up — that class of staleness is now gone for the
  wrapper scripts. Still applies if you invoke `rclone` directly by hand; see
  TROUBLESHOOTING. (`879a4d7`)
- `42password`'s own Windows secret files (`rclone-password-helper.ps1`,
  `rclone-password.enc`) now live under `$CONFIG_PATH`, not a separate
  hardcoded path — so a `configure-set config-path` override actually moves
  them. (`0e5f5be`)

### Shell-rc line management

- **Bug fixed:** the old `ensure_line()` only checked for an *exact* line
  match before appending — it never removed an older, different line for the
  same setting. Concretely: `configure-set bin-path X` followed by a
  reinstall left two `PATH` lines (old and new) in `~/.bashrc`, and the same
  for the tab-completion `source` line. New `ensure_line()` takes a pattern
  matching any prior version of that line and replaces it before appending
  the current one — reinstalling after a config change now reports
  "updated", not "added", and leaves exactly one line. (`238d0ba`)
- The duplicated bash/zsh shell-rc detection logic in `42sync_install.sh` and
  `42password` was unified into `bin/42-internal/lib/42-shell-rc.sh`
  (`detect_shell_rc`). Each caller keeps its own reaction to an unsupported
  shell — `42sync_install.sh` skips with a warning, `42password` refuses
  outright. (`bef88d0`)

### Completion and verb-list fixes

- `42logs` was never registered for tab-completion, so pressing `<TAB>`
  after it fell back to bash's default filename completion (listing the
  current directory). It now exposes a `__complete` mode (prints nothing —
  it has no verbs) and is registered alongside every other script.
  (`186f9b4`)
- `0ffcf9a`: every script now defers sourcing `42-common.sh` until *after*
  its own no-args/`__complete` check, so a hidden completion call can no
  longer trigger `42-common.sh`'s own first-run side effects (creating the
  per-machine override file, etc.) as a side effect of pressing `<TAB>`.
- `f97edfa`: `42password`'s `reinstall` description still compared itself to
  `42sync`'s bare `force` verb, which hasn't existed since the
  check/apply-pair naming pass — updated to name the actual current verbs
  (`force-check`/`force-apply`).

## Earlier

See `git log` for the full history before this stretch — notably the
original `bin`/verb-naming normalization (`check`/`apply` pairs,
`42projects`/`42logs` extracted from `42sync`, bash tab-completion added),
Windows support (DPAPI password storage, symlink/junction handling), and the
`42password`/`orphans`/`resync` features as they were first added.
