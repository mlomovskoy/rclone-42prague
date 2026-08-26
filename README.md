# rclone-42prague

Two-way sync between a 42 Prague campus machine and Google Drive, using
[rclone bisync](https://rclone.org/bisync/) and a personal Google OAuth client.

```
~/Projects            <-->   gdrive:_projects_rclone
  42Prague/                    42Prague/
    docs/                        docs/
    repos/                       repos/
```

## Why this exists

42 Prague cluster machines run Ubuntu with **local home directories**. `/home` is
part of the machine's own root filesystem, not a network mount — so your files do
not follow you to another seat. Drive is the thing that travels.

That makes the sync load-bearing, not a convenience:

- **Run `42sync` before you leave a seat.** Anything unsynced stays on that machine.
- **Run `42sync seed` when you sit at a new one.** Never plain `42sync` on an empty folder.
- **Git is your durable copy for code — where you can still push.** Push to vogsphere
  before you leave. Drive mirrors `.git` directories whole, but a mirror is not a remote.
  This advice has an exception worth knowing about: see *Repos you can no longer push*
  under Known limitations.

## Layout of this repo

```
README.md                    this file
TROUBLESHOOTING.md           every error hit during setup, and the fix
scripts/42install            installs the two below, plus rclone itself
scripts/42sync               the sync wrapper (install to ~/bin)
scripts/42links              docs/ and repos/ shortcuts into ~ (install to ~/bin)
templates/READ-ME-FIRST.txt  warning file that should be placed in ~/Projects
docs/                        GitHub Pages site (home / privacy / terms)
```

`docs/` exists only because Google requires a home page, privacy policy, and terms
of service URL on a real domain before an OAuth app can be published out of "Testing". It is served at
`https://<your-github-username>.github.io/rclone-42prague/`.

## Configuration

| Setting | Value |
|---|---|
| Google Cloud Console | `https://console.cloud.google.com/auth/` |
| Google Cloud project | `<42Prague>` (no organization) |
| OAuth app name | `rclone-42prague` |
| User type | External, publishing status **In production** |
| Scope | `https://www.googleapis.com/auth/drive.file` |
| OAuth client type | Desktop app, named `rclone` |
| Authorized domain | `<your-github-username>.github.io` |
| rclone remote | `gdrive` |
| Local path | `~/Projects` |
| Remote path | `gdrive:_projects_rclone` |
| bisync workdir | `~/.local/state/42sync/bisync` (**not** the default `~/.cache/...`) |
| Logs | `~/.local/state/42sync/*.log`, newest as `last.log` |
| Filters | `~/.config/rclone/projects-filters.txt` |

### The `drive.file` scope — read this before you wonder why a file is missing

rclone can only see files **it created itself**. This is the single most
surprising property of this setup.

- Anything you upload through drive.google.com is **invisible** to rclone. It will
  sit in the folder looking synced and never reach any machine. No error appears.
- `rclone lsd gdrive:` printing nothing is **correct**, not broken.
- Files must enter through the local side.

The tradeoff was deliberate: `drive.file` is a *non-sensitive* scope, which is why
this app could be published without going through Google's verification review.
Switching to full `auth/drive` later would require verification (multi-week) or new
grants get blocked.

### Where state lives, and why not `~/.cache`

bisync keeps "listings" — its record of what each side looked like last time. Without
them it cannot tell a change from a difference, and refuses to run.

rclone stores them in `~/.cache/rclone/bisync/` by default. **On these campus
machines `~/.cache` is emptied between login sessions** — verified by observing that
every directory in it (fontconfig, mesa_shader_cache, chrome…) carried a timestamp
from minutes after login, with nothing older surviving.

The effect was a forced `--resync` at the start of every session, which defeats the
point of two-way sync. `42sync` therefore passes `--workdir` and keeps listings in
`~/.local/state/42sync/bisync`, which does persist across logouts.

If you ever run `rclone bisync` by hand, pass `--workdir` too, or you will be
operating on a different (empty) baseline than the script.

### Publishing status

The app is published ("In production") rather than left in "Testing". In Testing,
Google expires refresh tokens after **7 days** — the sync would silently break every
week and demand re-authorization. Publishing removes that.

Cost of publishing: an unverified-app warning screen during `rclone config`
(*Advanced → Go to rclone-42prague (unsafe)*). Expected, harmless, one time.

## First-time setup on a new machine

```bash
# 1. Install rclone, 42sync and 42links into ~/bin -- no root required
git clone https://github.com/<your-github-username>/rclone-42prague.git
cd rclone-42prague
./scripts/42install
exec zsh                      # pick up the new PATH

# 2. Configure the remote
rclone config
#   n) new remote
#   name: gdrive
#   storage: drive
#   client_id / client_secret: from Google Cloud console -> Credentials -> rclone
#   scope: 3   (drive.file)
#   root_folder_id: (blank)
#   service_account_file: (blank -- press Enter, do not Ctrl-C)
#   Edit advanced config: n
#   Use web browser to automatically authenticate: y
#   Configure this as a Shared Drive: n

# 3. Encrypt the config (shared campus machine)
rclone config    # -> s) Set configuration password
chmod 600 ~/.config/rclone/rclone.conf

# 4. Seed from Drive
42sync seed

# 5. Create the ~/docs and ~/repos shortcuts
42links
```

`42install` ends by printing whichever of steps 2–5 still apply on this machine, so
you can tell what is left without re-reading this file. It downloads rclone as a plain
binary into `~/bin` (campus machines give you no admin rights) and verifies its SHA256
before installing. It deliberately stops short of `rclone config` and `42sync seed` —
both need decisions it should not make for you.

Re-run it any time to update the tools. It is idempotent: it only touches what has
actually changed, and `42install check` shows what it would do without doing it.

`42sync seed` refuses to run against a non-empty `~/Projects`. That is deliberate —
it exists to prevent a half-populated folder from being taken as the truth.

## Daily use

```bash
42sync           # two-way sync -- sitting down, and before leaving
42sync check     # dry run, changes nothing
42sync status    # local size, remote size, last run
42sync force     # push a directory rename through (asks twice)
42sync seed      # first run on a fresh machine only
```

`42links` maintains `docs` and `repos` shortcuts in `~`, `~/Documents` and `~/Downloads`,
pointing into the synced tree. They live in `$HOME`, so they are per-machine setup —
run it once per seat, like `42sync seed` and `rclone config`:

```bash
42links          # create or refresh the links
42links check    # dry run, changes nothing
42links status   # show current state, including broken links
42links clean    # remove only the links pointing into 42Prague/
```

Both scripts refuse to touch a real directory sitting where a link would go, and
`42links` refuses to run at all if a destination resolves inside `~/Projects` — a link
in there would be mirrored to Drive as a `.rclonelink` holding a per-machine path.

Logs: `~/.local/state/42sync/last.log`
Filters: `~/.config/rclone/projects-filters.txt` (created on first run, yours to edit)

Do not paste those `#` comments into zsh. Interactive zsh passes them as arguments
rather than stripping them; `setopt interactive_comments` in `~/.zshrc` fixes it.

## Safety mechanisms

These are not decoration. Each one exists because the failure it prevents is real
on a machine whose home directory can be wiped.

**`--check-access`** — refuses to sync unless an `RCLONE_TEST` marker file is present
on *both* sides. Without it, sitting at a fresh machine and running `42sync` out of
habit would present an empty local folder as "everything was deleted" and take your
Drive copy with it.

**`--max-delete 25`** — aborts if more than a quarter of files would disappear.
Second net under the first.

**`--links`** — stores symlinks as `.rclonelink` files. Without it rclone skips them
with a NOTICE that is easy to miss, and the file simply never syncs.

**Repo warning** — before running, `42sync` lists repos with uncommitted changes *and*
repos holding commits that were never pushed, because Drive is a mirror and mirrors do
not have history. The second list is the one to read carefully: see *Repos you can no
longer push* below.

## Known limitations

**Renaming directories is expensive.** bisync compares by path, so renaming a folder
reads as "every file inside was deleted, and an equal number appeared." The delete
guard will abort. This is correct behaviour; use `42sync force` and confirm the
dry run shows matched delete/create pairs. Reorganize *before* a sync, not between
syncs, when you can.

**Repos you can no longer push.** vogsphere revokes write access once a project has
been evaluated:

```
Gitea: Unauthorized — User <login> ... is not authorized to write to vogsphere/...
```

Nothing on your side fixes this, and it applies to your own repos as well as
teammate-owned ones. It inverts the rule at the top of this file: for those repos the
Drive copy of `.git` is the *only* off-machine copy of that history — which is exactly
what the next entry says not to rely on. `42sync` prints `unpushed commits: <repo>` so
you at least know which ones. The way out is a second remote you control:

```bash
cd ~/Projects/42Prague/repos/<repo>
git remote add github git@github.com:<your-github-username>/<repo>-history.git
git push github --all
```

Use `--all`, not a file copy. Copying the working tree preserves the code and loses
every commit, which for a repo whose value is its history is the wrong half.

**Never sync two machines at once.** Sequential is safe. Parallel produces
`.conflict` files, and inside a `.git` directory that gets unpleasant.

**A `.git` mirror is not a backup.** If a sync is interrupted mid-`.git`, that repo
can end up with a half-written index or dangling objects. Recoverable if you pushed;
painful if you did not.

**Every command prompts for the config password.** That is the cost of encrypting
it. For unattended runs use `--password-command` with `secret-tool` rather than
putting `RCLONE_CONFIG_PASS` in your shell profile — a world-readable rc file is not
an improvement over a world-readable config.

## Security notes

`~/.config/rclone/rclone.conf` contains the OAuth **refresh token** in plaintext
unless encrypted. That token grants access to the Drive files this app created,
without any password. On a shared campus filesystem this is the thing worth
protecting — more than the client secret, which alone cannot reach your data.

- Config is encrypted with a password; `chmod 600` as well.
- Revoke access any time at <https://myaccount.google.com/permissions>.
- The client secret can be rotated in the Cloud console.
- The app can be un-published back to Testing (which reinstates the 7-day expiry).
