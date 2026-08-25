# Troubleshooting

Every entry here is an error actually hit while setting this up, with what it really meant.

---

## `cannot find prior Path1 or Path2 listings`

```
ERROR : Bisync critical error: cannot find prior Path1 or Path2 listings,
        likely due to critical error on prior run
ERROR : Bisync aborted. Must run --resync to recover.
```

**Means:** bisync has no baseline for this exact path pair. Normal on a first run,
and also after you rename either side — the cached listings in
`~/.cache/rclone/bisync/` are keyed to the literal paths.

**Fix:** establish the baseline once.

```bash
rclone bisync ~/Projects gdrive:_projects_rclone \
  --filter-from ~/.config/rclone/projects-filters.txt \
  --check-access --max-delete 25 --links --resync --verbose
```

Do this when both sides are small or already identical. See the `--resync` warning
below before running it on a populated folder.

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

**Fix, if you are on a new machine:** `42sync seed`.

---

## `Safety abort: too many deletes (>25%)`

**Means:** you renamed or moved directories. bisync compares by path, so
`repos/repo_old_name_or_path/` → `repos/repo_new_name_or_path/` reads as XXX deletions plus 1 XXX creations.

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

## Inline `#` comments end up as arguments

Pasting a command with a trailing `# comment` into zsh passes the comment text as
arguments, because interactive zsh does not treat `#` as a comment by default.

```bash
setopt interactive_comments   # add to ~/.zshrc if you want them
```
