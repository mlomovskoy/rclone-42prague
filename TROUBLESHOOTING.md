# Troubleshooting

Every entry here is an error actually hit while setting this up, with what it
really meant.

---

## I edited a script in this repo, but running it shows no change

**Means:** you edited `scripts/42sync` (or `42links`/`42password`/
`42projects`/`42logs`) in a clone of this repo, but the copy on your `PATH`
resolves to the already-*installed* copy in `~/bin` — a separate file, not a
symlink back to the repo. Editing the source doesn't touch what actually
runs until you reinstall it. (This doesn't apply to `42sync_install.sh`
itself — it stays in the repo and is always run as `./42sync_install.sh`, so
its own edits take effect immediately.)

**Fix:**

```bash
./42sync_install.sh apply
```

Re-run it from the repo after every edit you want to actually test. It's
idempotent and only touches what changed (`cmp`-checks each script before
overwriting), so it's always safe to run.

---

## `cannot find prior Path1 or Path2 listings`

```
ERROR : Bisync critical error: cannot find prior Path1 or Path2 listings,
        likely due to critical error on prior run
ERROR : Bisync aborted. Must run --resync to recover.
```

**Means:** bisync has no baseline for this exact path pair. Normal on a first run,
and also after you rename either side — the cached listings in
`~/.local/state/42sync/bisync/` are keyed to the literal paths.

**Fix:**

```bash
42sync seed            # ~/Projects is empty, Drive is truth
42sync resync-check    # both sides already have real content (a laptop joining a
42sync resync-apply    # Drive folder a campus machine already seeded, say)
```

`resync-check`/`resync-apply` wrap a `rclone bisync --resync` with the same
dry-run-then-confirm guard as `force-check`/`force-apply` — `resync-apply` shows you
the full transfer plan and makes you type `RESYNC` before touching anything (unless
given it as an argument). Do not hand-type `rclone bisync --resync` yourself: it is
easy to drop a `--filter-from` your `projects-local.txt` needs, which silently
re-syncs something you meant to keep off this machine.

`--workdir` is what every mode passes so listings live in
`~/.local/state/42sync/bisync/` rather than `~/.cache`, which these machines clear
between sessions. See "The baseline disappears between sessions" below.

---

## The baseline disappears between sessions

**Symptom:** a sync succeeds, then hours later — after a logout, lunch, or a reboot —
the very next run fails with `cannot find prior Path1 or Path2 listings`. Nothing was
renamed and no run was interrupted.

**Cause:** rclone stores bisync listings in `~/.cache/rclone/bisync/` by default, and
the campus machines clear `~/.cache` between login sessions.

**Confirm it:**

```bash
ls -la ~/.cache/
```

If every directory carries a timestamp from just after your most recent login — with
nothing older — the whole cache is being wiped, not just rclone's part.

**Fix:** already applied in `42sync`, which passes
`--workdir ~/.local/state/42sync/bisync`. That location survives logout (verified by
logs written before a logout still being present after it).

If you run `rclone bisync` by hand, pass the same `--workdir`, otherwise you are
using a different, empty baseline and will be told to `--resync` again.

---

## `42sync resync-apply`'s log says "Bisync successful" but nothing was actually applied

**Means:** you're looking at the dry-run half, not the real one. This only
happens when `resync-apply` was run with **no** `RESYNC` argument — that
falls back to the interactive flow, which calls bisync twice into the *same*
log: once with `--dry-run` to show you what would happen, and again for real
only after you type `RESYNC` at the prompt. Both halves print "Bisync
successful" on completion; that phrase alone does not tell you which one
you're reading. (Running `42sync resync-check` first, then `42sync
resync-apply RESYNC`, avoids this entirely — each is its own invocation with
its own log, so there is nothing to confuse.)

**How to tell which one actually ran:** check whether the bisync workdir's
listing files were actually rewritten —

```bash
ls -la ~/.local/state/42sync/bisync/*.lst
```

(the plain `.path1.lst`/`.path2.lst` files, not the `-dry`/`-dry-new`/`-old`
variants). A completed real run always rewrites these, even when there was
"nothing to transfer" — persisting the listings is the whole point of a
resync. If their timestamp is older than your resync attempt, only the dry
run happened; the confirmation prompt is either still waiting in a terminal
somewhere, or the session was closed before you answered it (a plain Ctrl-C
or closed window at the `Type RESYNC to apply it for real:` prompt exits
immediately with no further log line, so an aborted attempt leaves no
"Aborted" message to distinguish it from a genuinely completed one).

**Fix:** find the terminal where you ran it and finish answering the prompt,
or re-run `42sync resync-apply` from scratch.

---

## `Access test failed: Path1 count 0, Path2 count 1 - RCLONE_TEST`

**Means:** `--check-access` did its job. The marker file exists on Drive but not
locally, so the local folder is not the one that was set up — wrong path, wiped
home, or a folder that was renamed/recreated.

**Do not** work around this by disabling `--check-access`. Find out why the marker
is gone first.

**Fix, if the local folder is genuinely correct and just lost the marker:**

```bash
touch ~/Projects/RCLONE_TEST
```

**Fix, if `~/Projects` is genuinely empty** (fresh account, or a machine outside the
campus): `42sync seed`. On a campus seat your home follows you, so an empty
`~/Projects` there means something went wrong — investigate before seeding over it.

---

## `Safety abort: too many deletes (>25%)`

**Means:** you renamed or moved directories. bisync compares by path, so
`repos/old_name/` → `repos/new_name/` reads as one deletion for every file in the old
tree plus one creation for every file in the new one. The run that first produced this
reported 1226 deletions and 1330 creations — 99% of the tree, far past the 25% ceiling.

**Verify first.** In the output, every `File was deleted` line should be an old path
and every `File is new` line its replacement. If the deletions surprise you, stop
and investigate — the guard may be catching a real problem.

**Fix:**

```bash
42sync force-check
42sync force-apply
```

`force-check` shows the dry run; `force-apply` requires you to type `FORCE`
before doing anything (or pass it as an argument to skip the prompt once
you've reviewed the dry run's log).

### Do NOT run `--resync` to fix this

Tempting, because earlier errors kept suggesting it. It would make things worse:
resync first copies Path2-only files *down* to Path1, recreating the old directory
names locally alongside your renamed ones. You end up with both structures on both
sides.

### Or: you just excluded (or removed) a project this sync already knew about

**A second, unrelated cause of the identical error message — with the
opposite fix.** If you ran `42projects exclude <ID>` (or deleted a folder
from Drive/local directly) right after a sync that still had it included,
bisync's baseline remembers those files from that last run. The very next
sync sees them vanish from the now-filtered view and reads that exactly like
a rename — "these files got deleted" — even though nothing was actually
removed, they simply stopped being tracked.

**How to tell which cause you're looking at:** run `42projects list` — if
the folder(s) behind the bulk of the deletes show as `excluded`, it's this
case, not a rename.

**Fix — the opposite of the rename case above:**

```bash
42sync resync-check
42sync resync-apply
```

**Not `force-apply`.** `force-apply` pushes through *real* deletions
(correct for a rename you actually want propagated to Drive). `resync-apply`
recomputes the baseline against the current filters and, per its own
documented guarantee, never deletes anything — exactly what's needed here,
since the excluded folder's Drive content should stay frozen and untouched,
not get purged. This is precisely how a `force-apply` run once already
touched `rclone-42prague`'s diverged `.git` for real after its exclusion
rule had gone missing — see "A repo's `.git` got corrupted by a bisync
conflict" below for that recovery.

---

## `failed to reload "filter" options: ... no such file or directory`

**Means:** you invoked `rclone` directly with `--filter-from` pointing at a file that
does not exist yet. `42sync` creates it on first run; raw rclone does not.

**Fix:**

```bash
cat > ~/.config/rclone/projects-filters.txt <<'EOF'
- .DS_Store
- .Trash-*/**
- **/*.o
- **/*.out
- a.out
- **/.cache/**
EOF
```

---

## Excluded files are stranded on Drive

**Symptom:** files you have since excluded in the filter file are still on Drive, and no
sync ever removes them. `rclone rmdirs` then fails on their directories:

```
ERROR : 42Prague/repos/.../objects: Failed to rmdir: googleapi: Error 403:
        The user may not have granted the app ... write access to all of the
        children of file ..., appNotAuthorizedToChild
ERROR : 42Prague/repos/.../.git: Failed to rmdir: directory not empty
```

**Means:** two separate things, both permanent.

Filters apply to the **destination** as well as the source. Once `*.out` is excluded,
`rclone sync` cannot see those files on Drive either — so it will never transfer them
and never delete them. Anything uploaded before you tightened the filters is now
invisible to every future run.

`appNotAuthorizedToChild` is the `drive.file` scope: rclone cannot remove a folder that
holds anything it did not create. Retrying does not help.

**Fix:** `42sync orphans-check` to see what is there, `42sync orphans-apply` to remove it.

It reads the exclude patterns out of your filter file and passes them as `--include`,
which is the only way to reach these files; lists what it found; shows a delete dry
run; and makes you type `DELETE` before touching anything (or pass it as an argument
to `orphans-apply` to skip the prompt).

By hand, if you prefer:

```bash
rclone ls     gdrive:_projects_rclone --include "**/*.out" --include "**/a.out"
rclone delete gdrive:_projects_rclone --include "**/*.out" --include "**/a.out" --dry-run -v
```

Note there is no `--filter-from` in those commands. Adding it would re-hide the very
files you are trying to reach — which is why these looked unreachable at first.
Deletions go to Drive's trash, so there is roughly a 30-day recovery window.

**The empty directories left behind are a separate problem.** `rclone rmdirs
gdrive:_projects_rclone --leave-root` clears the ones that become genuinely empty. Any
that still report `appNotAuthorizedToChild` never will, because that folder holds
something rclone did not create. Those are web-UI only — and cosmetic, since an empty
folder occupies no space.

bisync is unaffected by any of this: these files were never in its listings.

**Avoid it next time** by tightening filters *before* a large upload, not after.

---

## `Unauthorized ... is not authorized to write to vogsphere/...`

```
Gitea: Unauthorized — User <login> ... is not authorized to write to vogsphere/...
```

**Means:** vogsphere revoked write access because the project has been evaluated. It
affects your own repos as well as teammate-owned ones, and there is no setting to
change. This is not an SSH key problem — if the key were wrong you would get a
permission-denied from ssh, not an authorization message from Gitea.

**Consequence:** any local commits on that repo cannot leave the machine through git.
`42sync` reports these as `unpushed commits: <repo>` before each run.

**Fix:** push to a remote you control instead.

```bash
cd ~/Projects/42Prague/repos/<repo>
git remote add github git@github.com:<your-github-username>/<repo>-history.git
git push github --all
```

`--all` matters. A file-level copy into another folder preserves the working tree and
discards every commit, which for these repos is the half worth keeping.

---

## `~/.config/rclone/rclone.conf` doesn't exist (Windows)

**Means:** not broken — wrong path for this platform. Every `chmod 600
~/.config/rclone/rclone.conf` instruction in this README is written for
Linux/macOS. Native Windows builds of rclone default to `%APPDATA%\rclone\` (i.e.
`C:\Users\<you>\AppData\Roaming\rclone\rclone.conf`) instead — an XDG-style path
never applied there.

**Find the real path on any platform:**

```bash
rclone config file
```

**Fix the permissions on Windows:** `chmod 600` on that file will often report
success but leave the mode unchanged (`644`) — NTFS doesn't map cleanly onto POSIX
permission bits, so this is largely cosmetic on Windows rather than a sign
anything failed. It is not the security boundary there anyway: `%APPDATA%` is
already restricted by Windows to your own account by default, which is the actual
protection `chmod 600` exists to add on a shared Linux machine.

`42sync_install.sh`'s post-install check asks rclone itself for this path (`rclone config
file`) rather than hardcoding the Linux one, so it reports correctly on every
platform — but nothing else in this README does, so re-read `~/.config/rclone/...`
as "wherever `rclone config file` says" whenever you're on Windows.

---

## `Couldn't decrypt configuration, most likely wrong password`

**Means:** exactly that. rclone prompts again.

There is no recovery if the password is lost. Delete `rclone.conf`, re-run
`rclone config`, paste the client ID and secret from the Cloud console, and
re-authorize. The credentials still exist in Google Cloud; only the local token is
gone.

---

## `read: -p: no coprocess` (zsh, while setting up `--password-command`)

**Means:** a bash-style prompt-and-read one-liner was run in zsh:

```bash
read -s -p "rclone config password: " RCLONE_PW; echo
```

zsh's `read` has its own `-p`, meaning "read from a coprocess" — nothing to do with
bash's "show this prompt". zsh does not error on the unrelated meaning; it errors
because there is no coprocess to read from.

**Fix:** `42password` (see README, Known limitations) handles this itself now — it
prints its own prompt rather than passing one to `read`. Only relevant if you are
doing this by hand instead: print the prompt yourself, then read silently:

```bash
echo -n "rclone config password: "; read -s RCLONE_PW; echo
```

---

## `42links` says "created", but `42links status` shows "real dir (not a symlink)"

**Means:** on this Windows account, `ln -s` for a directory can succeed and produce
something that genuinely works for reading through — but isn't a real symlink bash's
own `[[ -L ]]` test recognizes. `42links` now tries the privileged, properly-detectable
path first (`MSYS=winsymlinks:nativestrict`) and only falls back to this if that is
refused outright — in which case it labels the link `created (as a working link this OS
wouldn't let bash create as a real symlink)` rather than claiming an ordinary success.

**If you see the plain `created` message** (not the fallback warning), you have a real,
managed symlink and nothing here applies.

**If you see the fallback warning:** the link works — `cd`, file access, everything
resolves through it correctly — but `42links status`/`clean-check`/`clean-apply` can
never recognize it as one of theirs again, since they all branch on `[[ -L ]]` too. This
is a Windows/MSYS limitation, not a bug to route around by hand: check whether Developer
Mode (Settings → Privacy & security → For developers) is off, or grant the account
`SeCreateSymbolicLinkPrivilege` directly via `secpol.msc` → Local Policies → User Rights
Assignment → Create symbolic links (same fix as the Piscine `.rclonelink` symlink-privilege
entry below) — then remove the existing fallback links and re-run `42links apply` to get
real ones.

---

## `Can't follow symlink without -L/--copy-links`

**Means:** a symlink was **skipped**. It is a NOTICE, not an error, and easy to miss
— the file simply never syncs and nothing tells you again.

**Fix:** `--links` is now in `42sync`, which stores symlinks as small `.rclonelink`
text files. Adding it makes previously-skipped symlinks appear as new files on the
next run.

---

## `symlinkat ... A required privilege is not held by the client` (Windows)

```
ERROR : 42Prague/repos/.../test6.rclonelink: Failed to copy: symlinkat test0
        42Prague\repos\...\test6: A required privilege is not held by the client.
ERROR : Bisync critical error: symlinkat ...
ERROR : Bisync aborted. Must run --resync to recover.
```

**Means:** Windows does not let a standard (non-admin) account create a real
symlink by default. `--links` downloads a symlink as a `.rclonelink` file and then
tries to recreate it as an actual symlink on disk — that last step is what fails.
One bad symlink is enough to abort the *entire* bisync run and invalidate its
baseline, even though everything else may have transferred cleanly — check the
summary above the error for `Transferred: N / N, 100%` before assuming anything
else was lost.

42's Piscine exercises use symlinks as test fixtures fairly often, so this is
likely to recur on a different file in a different exercise later. Excluding the
one path in the filter file is not a real fix.

**Fix — grant the privilege to one account (recommended if this machine has more
than one standard-user account):**

1. `Win+R` → `secpol.msc` → Enter (needs an admin credential once).
2. **Local Policies → User Rights Assignment** → **Create symbolic links**.
3. **Add User or Group** → the affected username → OK.
4. Log off and back on — user-rights changes apply at the next logon, not
   immediately.

This is the same mechanism Git for Windows' own docs recommend for symlink
support without admin rights, and it affects only the account added — another
standard account on the same machine is untouched. `secpol.msc` needs Windows Pro
or better; it does not exist on Home editions.

**Fix — Developer Mode (simpler, but machine-wide):**

Settings → Privacy & security → For developers → Developer Mode. This also works
(rclone's Go runtime uses the unprivileged-symlink-creation flag Windows exposes
under Developer Mode), but it is an `HKLM` (machine-wide) setting: it grants
**every** account on the machine the ability to sideload unsigned app packages,
not just symlink creation. Fine on a single-user machine; the scoped
`secpol.msc` fix above is the better default when other accounts share it.

**Then:** re-run `42sync resync-apply` (or whichever mode aborted) — the aborted run
leaves no valid baseline, but anything that already transferred does not need to
transfer again.

---

## `mv`/`rm -rf` on a directory fails with "Device or resource busy" (Windows)

**Means:** Windows locks a directory that is the *current working directory*
of any running process, or that has open file handles held by another program
(an editor watching the folder, an indexer, antivirus scanning it) — unlike
Linux, where renaming or removing a directory works fine even while something
has files open inside it. Renaming/removing the directory *itself* fails with
this error until whatever holds the lock releases it; individual files inside
it are usually still removable.

**Fix:** `cd` out of the directory first if your own shell is sitting inside
it — that alone is often the whole problem. If something else (an editor,
an indexer) holds the lock, either close it, or avoid renaming/removing the
top-level directory and work file-by-file inside it instead.

---

## A 42 exercise's filename can never be checked out (Windows)

**Means:** NTFS forbids several characters in filenames (`"`, `*`, `?`, `<`,
`>`, `|`, `:`) that POSIX filesystems allow. Some Piscine exercises
deliberately use one of these in a test fixture's filename. The file exists
fine in git's history and checks out normally on Linux, but can never be
materialized as an actual file on a native Windows checkout — Windows' file
APIs reject the name unconditionally, and no git configuration changes that.
`git status` reports it as permanently "deleted"; `git reset`/`git read-tree`
fail outright trying to write an index entry for it:

```
error: invalid path 'ex05/...'
fatal: make_cache_entry failed for path 'ex05/...'
```

**Not a bug, and there is no native-Windows fix.** The file is still viewable
without a checkout:

```bash
git show HEAD:'path/to/the/odd/file'
```

For an actual working checkout of it, see the README's "Windows: native Git
Bash, or WSL?" — only a real POSIX filesystem (WSL, or the original campus
Linux machine) can hold this filename at all.

**If this file's index entry gets corrupted** (e.g. by a bisync conflict —
see the symlink-privilege entry above for how that happens), rebuilding the
index the normal way (`git reset` / `git read-tree HEAD`) will fail on this
exact path, the same error as above. Restore the index from a known-good
copy instead of trying to reconstruct it locally — a Drive-synced
`index.conflict1`/`.conflict2` backup from before the corruption, or a fresh
copy pulled from wherever the repo is also cloned:

```bash
rclone copyto "gdrive:_projects_rclone/<repo-path>/.git/index.conflict1" .git/index
```

`index.conflict1` is generally the machine's own last-known-good index (per
the `Renaming Path1 copy` vs `Path2 copy` wording bisync logs when it creates
these) — `.conflict2` is the other side's. Check `git status` afterward:
alongside the always-permanent "deleted" line for the tricky-filename entry,
it should show only real, believable modifications — not every tracked file
as deleted-and-untracked.

---

## `~/.config/rclone/projects-local.txt` loses its exclude rules — cause not yet known

**Status: unresolved.** Documented so the symptom is recognized before it
causes damage again, not because there's a fix yet.

**What happened:** `projects-local.txt` had working `- /rclone-42prague/**`
and `- /mac-device-management/**` rules, both confirmed present earlier in
the same session. Later the same day, the file was found reduced to just its
header comment — both rules gone, with no `42projects include` ever
run and no manual edit made to it. The very next `42sync force-apply` then
synced `rclone-42prague`'s `.git` for real, producing the whole-tree
conflict corruption documented above — this file's rules disappearing is
what removed the guard that would have prevented that.

**What's been ruled out:** nothing in `42sync`/`42projects` writes to this
file except `42projects include`/`exclude` (neither was run in between). It
lives under `~/.config`, entirely outside `$LOCAL`, so bisync itself cannot
touch it — this isn't a sync side-effect. No other process on this machine
is known to touch it.

**If you notice your exclusions are gone:** before running `force-apply` or
`apply`, run `42projects list` and re-add anything that should be excluded
(`42projects exclude <ID>`) — re-establishing the rules is quick and
safe. Treat an unexpectedly-empty `projects-local.txt` as a signal to check
carefully before your next sync, not as something to shrug off — it's exactly
the precondition for the corruption case above.

---

## A repo's `.git` got corrupted by a bisync conflict (whole tree, not just the index)

**Symptom:** `git status` reports "No commits yet" or similarly broken
output. Every tracked file has a `.conflict1`/`.conflict2` pair, including
`.git/config`, `.git/index`, and `.git/refs/heads/<branch>` themselves —
not just one file, the whole tree. `git fsck` may report nothing useful
because there's no valid `.git/config` for git to even operate against.

**Means:** the repo's `.git/` was being synced whole (the current default —
see "Renaming directories is expensive" and the vogsphere-write-revocation
entries elsewhere in this file for why that's the design), and its local and
Drive copies had genuinely diverged — normal after enough independent work on
each side without an intervening sync. bisync compared every file, found
them all different, and conflict-renamed all of them rather than picking a
side.

**This looks catastrophic but usually isn't, if the repo has a remote you
can still reach.** The actual commit history lives in `.git/objects`, which
bisync's conflict handling does not touch — only the *pointers* to it
(`config`, `index`, `refs`, `HEAD`) get conflict-renamed. If `origin` (or any
other configured remote) still has the real history, recovery is a fresh
clone, not manual repair:

1. **Before touching anything, check for uncommitted work worth saving.**
   Every tracked file is duplicated as `.conflict1`/`.conflict2` right now —
   if you had *uncommitted* local changes, they're preserved in whichever
   conflict variant is newer (check `ls -la` timestamps). Copy anything you
   need somewhere outside the repo first.
2. **Clone a known-good copy into a separate temp folder** — don't clone
   directly on top of the broken one:
   ```bash
   git clone <remote-url> ../repo-name-fresh
   ```
3. **Replace the broken `.git` with the fresh one:**
   ```bash
   rm -rf .git
   cp -r ../repo-name-fresh/.git .git
   ```
4. **Delete every conflict file** (safe now — step 1 already saved anything
   that mattered):
   ```bash
   find . \( -iname "*.conflict1" -o -iname "*.conflict2" \) -delete
   ```
   Note the parentheses: `find . -iname "*.conflict1" -o -iname "*.conflict2"
   -delete` (no grouping) silently only deletes matches for the *second*
   pattern — `-delete` binds to the nearest condition, not the whole
   expression, and `find` gives no warning that it did this.
5. **Restore the real files from the now-healthy git:**
   ```bash
   git checkout -- .
   ```
6. **Verify:** `git status` should show clean (or only genuinely
   uncommitted work), `git fsck --full` should report nothing, `git log`
   should show real history.
7. **Clean up the stray conflict files left on Drive too** — bisync creates
   them on both sides. `42sync orphans-apply` won't catch these (they're not
   artifact-filter excludes), so remove them directly:
   ```bash
   rclone delete "gdrive:_projects_rclone/<repo-path>" --include "*.conflict*"
   ```
8. **The bisync baseline is now stale relative to reality** (it still
   remembers the pre-recovery state) — expect `42sync check`/`apply` to trip
   the delete guard next, and fix it with `42sync resync-check`/`resync-apply`,
   not `force-apply` — see "Safety abort: too many deletes" above for why
   that distinction matters.

**If there is no reachable remote** (a vogsphere repo with write access
already revoked, and no secondary GitHub remote — see "Known limitations" in
the README): the `.conflict1`/`.conflict2` pairs are the only recovery path.
Compare their contents by hand and reconstruct manually; there is no
shortcut here for a repo that doesn't have a GitHub remote yet.

---

## `rclone lsd gdrive:` prints nothing

**Not a bug.** With the `drive.file` scope rclone can only see files it created. An
empty listing is the expected result.

Use `rclone about gdrive:` as the connectivity test instead — it prints your quota,
which proves the token works.

---

## Files added through drive.google.com never arrive

**Not a bug, and there is no fix.** `drive.file` grants access only to files the app
itself created. Web-uploaded files are invisible to rclone permanently.

Put files in `~/Projects/` and run `42sync apply`.

---

## "Google hasn't verified this app" during `rclone config`

**Expected.** The app is published but unverified, which is fine for personal use
with a non-sensitive scope.

Click **Advanced** → **Go to rclone-42prague (unsafe)**.

---

## `Publish app` is greyed out in the Cloud console

**Means:** the OAuth Branding page is incomplete. App name, support email, and
developer contact are not enough — publishing an External app also requires the
**App domain** block: application home page, privacy policy link, terms of service
link, and at least one authorized domain.

That is what `docs/` in this repo is for. Set:

```
Home page:      https://<your-github-username>.github.io/rclone-42prague/
Privacy policy: https://<your-github-username>.github.io/rclone-42prague/privacy.html
Terms:          https://<your-github-username>.github.io/rclone-42prague/terms.html
Authorized domain: <your-github-username>.github.io
```

The authorized domain takes **no protocol and no path**. It must also be
`<your-github-username>.github.io`, not bare `github.io` — because `github.io` is on the Public
Suffix List, the subdomain is the "top private domain" Google wants.

---

## Clicking Save in the Cloud console appears to do nothing

Seen while adding a test user: the panel closed, no error, nothing saved. Cause was a
password-manager browser extension popup overlaying the page and swallowing the
click.

**Fix:** dismiss extension popups, then retry. Reload and confirm the change
actually persisted rather than trusting the closed dialog.

---

## Bisync is very slow

Thousands of small files — especially `.git` object directories — are the worst case
for the Drive API, which has no batching available under this scope. A few thousand
objects taking several minutes is normal.

Reduce the file count rather than chasing throughput: keep build artifacts out via
the filter file (`*.o`, `*.out`, `a.out` are already excluded).

---

## `42sync check` is clean but `42sync verify` fails

**Means:** bisync's baseline agrees with neither side. `check` compares against that
stored record and sees nothing to do; `verify` compares real content and finds files
missing on Drive. When they disagree, the baseline is what is wrong — not your files.

This is the state an interrupted run leaves: the data work finished, the listings were
never written, or were written from a tree that no longer matches.

**Fix:** make the two sides genuinely agree first, then rebuild the record.

```bash
42sync verify   # note exactly what is missing
42sync apply    # a normal sync usually resolves it
42sync verify   # confirm
```

If `verify` still fails after a successful sync, push local up one-way and re-baseline —
in that order, and only once you are certain local is the copy you want to keep:

```bash
tmux new -s sync
rclone sync ~/Projects gdrive:_projects_rclone \
  --filter-from ~/.config/rclone/projects-filters.txt \
  --links --verbose 2>&1 | tee ~/.local/state/42sync/mirror-$(date +%F-%H%M).log

rclone bisync ~/Projects gdrive:_projects_rclone \
  --workdir ~/.local/state/42sync/bisync \
  --filter-from ~/.config/rclone/projects-filters.txt \
  --check-access --max-delete 25 --links --resync --verbose
```

`rclone sync` is one-way and idempotent, so an interruption costs nothing — unlike the
`--resync` that follows it. Do the mirror first: it makes both sides identical, which is
the only state in which `--resync` cannot resurrect anything you deleted.

---

## `SHA256SUMS is not validly signed`

**Means:** `42sync_install.sh` fetched rclone's checksum file, but it was not signed by the key
this repo pins. Either the download was corrupted or truncated, or something between
you and `downloads.rclone.org` altered it. Nothing was installed.

**Do not work around this** by skipping the check. Retry first — a truncated fetch on a
flaky network is the likeliest cause by a wide margin:

```bash
./42sync_install.sh reinstall
```

If it fails again, verify by hand before going further:

```bash
curl -fsSLO https://downloads.rclone.org/v1.75.0/SHA256SUMS
gpg --keyserver hkps://keys.openpgp.org \
    --recv-keys FBF737ECE9F8AB18604BD2AC93935E02FF3B54FA
gpg --verify SHA256SUMS
```

A "Good signature" there but a failure in `42sync_install.sh` points at the bundled
`scripts/rclone-release-key.asc`. A bad signature there too means the problem is
upstream or on your network, and installing rclone from that source is not safe.

**Related:** `Bundled signing key is <X>, but this script pins <Y>` means
`scripts/rclone-release-key.asc` is not the key the script expects — it was replaced,
corrupted, or the pin was edited. Restore it from git.

---

## `Cannot verify rclone's signature: gpg is not installed`

**Means:** `42sync_install.sh` verifies rclone's signature by default and will not install
without it. Nothing was installed.

**Fix:** use a machine that has `gpg` — most Linux and macOS installs do, and the campus
machines do. If the key file is what is missing instead, restore it:

```bash
git checkout scripts/rclone-release-key.asc
```

If `gpg` is genuinely unavailable and you cannot install it (no admin rights on a campus
machine), you can proceed with the SHA256 check alone. It catches a corrupted download
but not a tampered mirror, so decide deliberately:

```bash
INSTALL_ALLOW_UNSIGNED=1 ./42sync_install.sh apply
```

---

## A project on Drive never arrives on this machine

**First check whether you excluded it on purpose:**

```bash
42projects list
```

Anything listed as `excluded` is being skipped by this machine by design, and its Drive
copy is untouched. `42projects include <ID>` brings it back on the next sync.

If it is listed as `synced` but still does not arrive, the cause is the `drive.file`
scope, not the filters — see *Files added through drive.google.com never arrive*. A file
put on Drive through the web is invisible to rclone permanently, whatever the filters
say.

---

## An `RCLONE_*` variable breaks every rclone command

**Symptom:** rclone fails or prints nothing for no visible reason — including commands
as trivial as `rclone version`. Tools that shell out to rclone then report it as
missing or broken.

**Means:** rclone reads any `RCLONE_<FLAG>` variable in the environment as `--<flag>`.
So `RCLONE_VERSION=1.75.0` becomes `--version=1.75.0`, and because `--version` is a
boolean flag, every single invocation dies during argument parsing.

This is easy to trip over accidentally, because the namespace looks like an ordinary
prefix rather than a reserved one. `42sync_install.sh` takes its version pin from
`INSTALL_RCLONE_VERSION` for exactly this reason.

**Confirm:**

```bash
env | grep ^RCLONE_
```

**Fix:** unset or rename whatever is listed. `RCLONE_CONFIG_PASS` is the one member of
this namespace you might legitimately set — and even then, prefer
`--password-command` (see README, Known limitations).

---

## Inline `#` comments end up as arguments

Pasting a command with a trailing `# comment` into zsh passes the comment text as
arguments, because interactive zsh does not treat `#` as a comment by default.

```bash
setopt interactive_comments   # add to ~/.zshrc if you want them
```

---

## A command appears to hang, doing nothing

If it touches the rclone config, it is probably waiting for the config password with
the prompt hidden. rclone writes that prompt to **stderr**, so any command wrapped in
`2>/dev/null` blocks silently on invisible input.

Type the password and press Enter. And never suppress stderr on a command that can
prompt — it converts "asking you something" into "hung for no reason".
