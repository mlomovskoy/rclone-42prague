# Troubleshooting

Every entry here is an error actually hit while setting this up, with what it
really meant.

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

**Fix:** establish the baseline once.

```bash
rclone bisync ~/Projects gdrive:_projects_rclone \
  --workdir ~/.local/state/42sync/bisync \
  --filter-from ~/.config/rclone/projects-filters.txt \
  --check-access --max-delete 25 --links --resync --verbose
```

`--workdir` matters: without it rclone uses `~/.cache`, which these machines clear
between sessions. See "The baseline disappears between sessions" below.

Do this when both sides are small or already identical. See the `--resync` warning
below before running it on a populated folder.

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
42sync force
```

It shows a dry run and requires you to type `FORCE` before doing anything.

### Do NOT run `--resync` to fix this

Tempting, because earlier errors kept suggesting it. It would make things worse:
resync first copies Path2-only files *down* to Path1, recreating the old directory
names locally alongside your renamed ones. You end up with both structures on both
sides.

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

## Excluded files are stranded on Drive forever

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

**Fix:** delete them from the Drive web UI. You own the files even where the app does
not have access. Web-side deletion is safe here *only* because these paths exist in
neither the local tree nor the bisync baseline, so bisync never sees the change — the
usual "never touch it from the web" rule does not apply to already-orphaned files.

To find them before deciding:

```bash
rclone ls gdrive:_projects_rclone --include "**/*.out" --include "**/a.out"
```

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

## `Couldn't decrypt configuration, most likely wrong password`

**Means:** exactly that. rclone prompts again.

There is no recovery if the password is lost. Delete `rclone.conf`, re-run
`rclone config`, paste the client ID and secret from the Cloud console, and
re-authorize. The credentials still exist in Google Cloud; only the local token is
gone.

---

## `Can't follow symlink without -L/--copy-links`

**Means:** a symlink was **skipped**. It is a NOTICE, not an error, and easy to miss
— the file simply never syncs and nothing tells you again.

**Fix:** `--links` is now in `42sync`, which stores symlinks as small `.rclonelink`
text files. Adding it makes previously-skipped symlinks appear as new files on the
next run.

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

Put files in `~/Projects/` and run `42sync`.

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
42sync verify           # note exactly what is missing
42sync                  # a normal sync usually resolves it
42sync verify           # confirm
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

**Means:** `42install` fetched rclone's checksum file, but it was not signed by the key
this repo pins. Either the download was corrupted or truncated, or something between
you and `downloads.rclone.org` altered it. Nothing was installed.

**Do not work around this** by skipping the check. Retry first — a truncated fetch on a
flaky network is the likeliest cause by a wide margin:

```bash
./scripts/42install force
```

If it fails again, verify by hand before going further:

```bash
curl -fsSLO https://downloads.rclone.org/v1.75.0/SHA256SUMS
gpg --keyserver hkps://keys.openpgp.org \
    --recv-keys FBF737ECE9F8AB18604BD2AC93935E02FF3B54FA
gpg --verify SHA256SUMS
```

A "Good signature" there but a failure in `42install` points at the bundled
`scripts/rclone-release-key.asc`. A bad signature there too means the problem is
upstream or on your network, and installing rclone from that source is not safe.

**Related:** `Bundled signing key is <X>, but this script pins <Y>` means
`scripts/rclone-release-key.asc` is not the key the script expects — it was replaced,
corrupted, or the pin was edited. Restore it from git.

---

## `Cannot verify rclone's signature: gpg is not installed`

**Means:** `42install` verifies rclone's signature by default and will not install
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
INSTALL_ALLOW_UNSIGNED=1 ./scripts/42install
```

---

## An `RCLONE_*` variable breaks every rclone command

**Symptom:** rclone fails or prints nothing for no visible reason — including commands
as trivial as `rclone version`. Tools that shell out to rclone then report it as
missing or broken.

**Means:** rclone reads any `RCLONE_<FLAG>` variable in the environment as `--<flag>`.
So `RCLONE_VERSION=1.75.0` becomes `--version=1.75.0`, and because `--version` is a
boolean flag, every single invocation dies during argument parsing.

This is easy to trip over accidentally, because the namespace looks like an ordinary
prefix rather than a reserved one. `42install` takes its version pin from
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
