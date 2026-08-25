# rclone-42prague

Two-way sync between a 42 Prague campus machine and Google Drive, using
[rclone bisync](https://rclone.org/bisync/) and a personal Google OAuth client.

```
~/Projects            <-->   gdrive:_projects_rclone
```

## Why this exists

42 Prague cluster machines run Ubuntu with **local home directories**. `/home` is
part of the machine's own root filesystem, not a network mount — so your files do
not follow you to another seat. Drive is the thing that travels.

That makes the sync load-bearing, not a convenience:

- **Run `42sync` before you leave a seat.** Anything unsynced stays on that machine.
- **Run `42sync seed` when you sit at a new one.** Never plain `42sync` on an empty folder.
- **Git is still your durable copy for code.** Push to vogsphere before you leave.
  Drive mirrors `.git` directories whole, but a mirror is not a remote.

## Layout of this repo

```
README.md                  this file
TROUBLESHOOTING.md         every error hit during setup, and the fix
scripts/42sync             the sync wrapper (install to ~/bin)
templates/READ-ME-FIRST.txt  warning file that should be places in ~/Projects
docs/                      GitHub Pages site (home / privacy / terms)
```

`docs/` exists only because Google requires a home page, privacy policy, and terms
of service URL on a real domain before an OAuth app can be published out of "Testing". It is served at
`https://<your-github-username>.github.io/rclone-42prague/`.

## Configuration


|Google Cloud Console | `https://console.cloud.google.com/auth/`|
| Google Cloud project | `<42Prague>` (no organization) |
| OAuth app name | `rclone-42prague` |
| User type | External, publishing status **In production** |
| Scope | `https://www.googleapis.com/auth/drive.file` |
| OAuth client type | Desktop app, named `rclone` |
| Authorized domain | `<your-github-username>.github.io` |
| rclone remote | `gdrive` |
| Local path | `~/Projects` |
| Remote path | `gdrive:_projects_rclone` |

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

### Publishing status

The app is published ("In production") rather than left in "Testing". In Testing,
Google expires refresh tokens after **7 days** — the sync would silently break every
week and demand re-authorization. Publishing removes that.

Cost of publishing: an unverified-app warning screen during `rclone config`
(*Advanced → Go to rclone-42prague (unsafe)*). Expected, harmless, one time.

## First-time setup on a new machine

```bash
# 1. Install the script
mkdir -p ~/bin
cp scripts/42sync ~/bin/ && chmod +x ~/bin/42sync
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc

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
```

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

Logs: `~/.local/state/42sync/last.log`
Filters: `~/.config/rclone/projects-filters.txt` (created on first run, yours to edit)

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

**Uncommitted-repo warning** — `42sync` lists repos with uncommitted changes before
running, because Drive is a mirror and mirrors do not have history.

## Known limitations

**Renaming directories is expensive.** bisync compares by path, so renaming a folder
reads as "every file inside was deleted, and an equal number appeared." The delete
guard will abort. This is correct behaviour; use `42sync force` and confirm the
dry run shows matched delete/create pairs. Reorganize *before* a sync, not between
syncs, when you can.

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
