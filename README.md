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

Your home directory **does follow you between seats**. It is a per-user volume
attached at login — on a campus machine it shows up as its own device mounted at
`/home/<login>`:

```
df -h /home    ->  /dev/mapper/ubuntu--vg-ubuntu--lv--root   /     # the root fs
df -h $HOME    ->  /dev/sda                                  /home/<login>
```

Check `$HOME`, not `/home`. `/home` itself lives on the machine's root filesystem, so
looking there suggests homes are local and per-machine. They are not — the per-user
volume is mounted one level deeper. Verified by logging into a second seat and finding
`~/bin`, `~/Projects`, `~/.config/rclone` and the bisync baseline all present.

So this sync is **not** the mechanism that carries work between seats — that already
works. What it is for:

- **An off-machine copy.** The home volume is a single point of failure, and it is
  yours alone. Nothing else backs it up.
- **Reach from outside the campus.** Your own laptop, via the same Drive folder.
- **A second copy of git history you cannot push.** See *Repos you can no longer push*
  under Known limitations — for those repos there is no remote to fall back on.

Three habits still matter:

- **Run `42sync` when you finish something worth not losing.** Not because the seat
  will eat it, but because one volume is one copy.
- **`42sync seed` is for an empty `~/Projects`, not for a new seat.** On a campus
  machine your files are already there — run `42sync check` instead.
- **Git is your durable copy for code — where you can still push.** Push to vogsphere
  while you can; access is revoked once a project is evaluated. Drive mirrors `.git`
  directories whole, but a mirror is not a remote.
  This advice has an exception worth knowing about: see *Repos you can no longer push*
  under Known limitations.

## Layout of this repo

```
README.md                    this file
TROUBLESHOOTING.md           every error hit during setup, and the fix
scripts/42install            installs the two below, plus rclone itself
scripts/rclone-release-key.asc  rclone's release signing key, used by 42install
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

## First-time setup

Once per home volume, not once per seat — on a campus machine the tools and config
follow you. You need this on a genuinely fresh account, or on a machine outside the
campus (your own laptop).

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
binary into `~/bin` (campus machines give you no admin rights), and checks it against a
SHA256 that has itself been PGP-verified against rclone's release key before installing
anything — see *Verifying the rclone download* under Security notes. It deliberately
stops short of `rclone config` and `42sync seed` — both need decisions it should not
make for you.

Re-run it any time to update the tools. It is idempotent: it only touches what has
actually changed, and `42install check` shows what it would do without doing it.

Every run writes `~/.local/state/42sync/install-<timestamp>.log` (see *Logs* under
Daily use). It keeps what the terminal does not: the exact URLs fetched, `curl`'s own
error text (it runs silent), the full gpg output, and — when a signature or checksum
check fails — the `SHA256SUMS` as received. That evidence would otherwise die with the
temp directory.

`42sync seed` refuses to run against a non-empty `~/Projects`. That is deliberate —
it exists to prevent a half-populated folder from being taken as the truth.

## Daily use

```bash
42sync           # two-way sync -- sitting down, and before leaving
42sync check     # dry run, changes nothing
42sync verify    # compare real content: is everything local actually on Drive?
42sync status    # local size, remote size, last run
42sync force     # push a directory rename through (asks twice)
42sync orphans   # delete excluded files stranded on Drive (asks twice)
42sync orphans check   # list them and stop -- deletes nothing
42sync projects  # choose which projects sync to THIS machine
42sync seed      # only when ~/Projects is empty (fresh account / other machine)
```

### `check` and `verify` answer different questions

`42sync check` asks bisync what it would do, and bisync answers from its
**baseline** — its stored record of what both sides looked like last time. That is
what you want before a sync.

`42sync verify` ignores the baseline and compares **actual content**, hash by hash. It
is the one that answers "is my work really backed up", and it can catch the failure a
baseline structurally cannot: both sides agreeing on a record that is itself wrong,
which is what an interrupted run can leave behind.

Run `verify` when it matters — before wiping a machine, after any interrupted sync, or
whenever you want to stop wondering. It is read-only and safe to interrupt; it reads
both sides in full, so it is not fast.

If `check` says "No changes found" but `verify` fails, the baseline is the thing that
is wrong — see TROUBLESHOOTING.md before reaching for `--resync`.

`42links` maintains `docs` and `repos` shortcuts in `~`, `~/Documents` and `~/Downloads`,
pointing into the synced tree. They live in `$HOME`, so on a campus machine they
follow you and you only need this once:

```bash
42links          # create or refresh the links
42links check    # dry run, changes nothing
42links status   # show current state, including broken links
42links clean    # remove only the links pointing into 42Prague/
```

Both scripts refuse to touch a real directory sitting where a link would go, and
`42links` refuses to run at all if a destination resolves inside `~/Projects` — a link
in there would be mirrored to Drive as a `.rclonelink` holding a per-machine path.

### Choosing what this machine carries

Not every project belongs on every machine. `~/Projects` is one folder on Drive, but a
laptop project does not need to land on a campus machine:

```bash
42sync projects                  # what syncs here, and what does not
42sync projects diff MacApp      # compare the two copies before deciding
42sync projects exclude MacApp   # stop carrying it here
42sync projects include MacApp   # carry it again
```

```
STATUS    FOLDER                   WHERE
synced    42Prague                 local + Drive
excluded  MacApp                   local + Drive    both copies exist -> projects diff MacApp
excluded  DriveOnly                Drive only
stale     GhostFolder              -                rule matches nothing; drop it
```

**Top-level folders under `~/Projects` only.** A rule is anchored to the sync root, so a
deeper path is easy to get wrong and fails silently when you do — `exclude` refuses a
name it cannot find on either side, and `list` marks a rule that matches nothing as
`stale`.

An exclusion is **not** a deletion and not a filter on Drive. The remote copy is simply
never looked at: not transferred, not deleted, left exactly as it is, so the machine
that owns that project keeps syncing it normally. Re-include it and the next sync pulls
it back down — no `--resync` needed.

Excluding something already on this machine leaves the files on disk; they just stop
syncing. Delete them yourself to reclaim space, and that deletion will not reach Drive,
because the path is filtered out by then.

#### Before re-including a folder that exists on both sides

This is the one case that can get untidy, so there is a command for it:

```bash
42sync projects diff MacApp
```

It compares real content — identical, only here, only on Drive, differing — shows the
newest change on each side, and then says plainly which of four situations you are in.
If only one side has changes, including it just moves them across. If **both** sides
have changes, bisync will do a genuine two-way merge: files changed on one side move,
files changed on both become `.conflict` pairs for you to resolve by hand. Nothing is
lost either way, but `diff` lets you pick a winner first with a one-way `rclone sync`
instead, and prints the exact command.

`diff` is read-only and ignores the exclusion, so it works on a folder you are not
currently syncing.

The selection lives in `~/.config/rclone/projects-local.txt`, which is **per-machine and
never synced** — that is the whole point. It is deliberately a different file from the
artifact filters below, because `42sync orphans` treats everything the artifact filters
exclude as junk on Drive and offers to delete it. A project you are keeping on Drive on
purpose must never appear in that list.

#### Deleting a folder from Drive

```bash
42sync projects exclude MacApp    # first: protect the local copy
42sync projects delete  MacApp    # then: remove it from Drive
```

The order matters, and the command enforces it. If a folder is **still syncing** and a
copy is on this machine, deleting it from Drive would make the next `42sync` read that
as "deleted on Path2" and remove your local copy too. `delete` refuses in that case and
tells you to exclude it first. Once excluded, the path is filtered out and nothing
propagates in either direction, so the local copy is safe.

`delete` shows the object count and size, warns that this removes the folder **for every
machine**, runs a `--dry-run` purge, and makes you type the folder name before doing
anything. It is a terminal command — no web interface involved. The exclusion works only
because filters hide the path from *sync*; `rclone purge` addresses the remote path
directly and never reads them.

Afterwards the exclusion rule is left in place on purpose: with the folder gone from
Drive, that rule is now the only thing stopping the next sync from uploading your local
copy straight back up.

The one case that does need drive.google.com is a purge failing with
`appNotAuthorizedToChild` — that folder holds something rclone did not create, and under
the `drive.file` scope no rclone command can remove it.

Filters: `~/.config/rclone/projects-filters.txt` (artifact excludes: `*.o`, `*.out`,
caches — shared intent on every machine, created on first run, yours to edit)

### Logs

Every run of every script writes its own log and prints the path as its **last line**,
whether it succeeded, failed or was aborted — with one deliberate exception,
`42sync logs`, which exists to list the logs and would otherwise change what it
reports:

```
Log: /home/<login>/.local/state/42sync/verify-2026-08-31-142752.log
```

All three scripts write to `~/.local/state/42sync/`, so there is one place to look:

| Prefix | Written by |
|---|---|
| `sync-` `check-` `verify-` `force-` `orphans-` `seed-` `status-` | `42sync`, named after the mode |
| `install-` | `42install` |
| `links-<mode>-` | `42links` |

`last.log` symlinks to the most recent `42sync` run of any mode. Each script keeps its
own newest 20 and prunes only its own prefixes, so none can delete another's evidence.
`42sync logs` lists what is there, and writes nothing itself.

That directory is deliberately **not** `~/.cache`, which these machines wipe between
logins — see *Where state lives* above.

Do not paste those `#` comments into zsh. Interactive zsh passes them as arguments
rather than stripping them; `setopt interactive_comments` in `~/.zshrc` fixes it.

## Safety mechanisms

These are not decoration. Each one exists because the failure it prevents actually
happened during setup.

**`--check-access`** — refuses to sync unless an `RCLONE_TEST` marker file is present
on *both* sides. Without it, running `42sync` against an empty or wrong `~/Projects`
would present it as "everything was deleted" and take your Drive copy with it. That is
not hypothetical: it fired correctly during setup when the local folder had been
renamed out from under it.

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

### Verifying the rclone download

`42install` fetches a binary over the network and makes it executable, so it verifies
what it got before trusting it:

1. Downloads the versioned zip and its `SHA256SUMS`, which rclone publishes PGP-clearsigned.
2. Imports `scripts/rclone-release-key.asc` into a **throwaway keyring** — never your
   `~/.gnupg` — and refuses to continue unless that key's fingerprint is exactly:

   ```
   FBF737ECE9F8AB18604BD2AC93935E02FF3B54FA   Nick Craig-Wood <nick@craig-wood.com>
   ```

3. Verifies the signature and asserts the *signer*. `gpg --verify` exits 0 for a good
   signature from any key in the keyring, so the exit status alone proves nothing.
4. Reads the checksum from `gpg --decrypt` output rather than from the file. A
   clearsigned file's signature covers only the payload, so unsigned lines can sit
   outside it — verifying the file and then grepping the file is a known way to be
   fooled.
5. Compares that checksum against the downloaded zip.

Do not take the fingerprint above on trust from this file alone. Cross-check it against
<https://rclone.org/release_signing/> and a keyserver; a fingerprint is only worth
something if you have seen it in more than one place.

Verification is required, not best-effort. If the signature cannot be checked — no
`gpg`, or a missing or replaced key file — `42install` installs nothing and says why.
`42install check` tells you in advance whether this machine can verify.

Campus machines give you no admin rights, so if `gpg` really is absent you cannot
simply install it. To proceed anyway, accepting that only the SHA256 is checked — which
catches a corrupted download but not a tampered mirror — opt out explicitly:

```bash
INSTALL_ALLOW_UNSIGNED=1 ./scripts/42install
```

It has to be typed. That is the point: skipping verification should be a decision, not
something you fall into by running on a machine that happens to lack `gpg`.
