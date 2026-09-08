# rclone-42prague

Two-way sync between a 42 Prague campus machine and Google Drive, using
[rclone bisync](https://rclone.org/bisync/) and a personal Google OAuth client.

```
~/Projects            <-->   gdrive:_projects-sync-rclone
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
CHANGELOG.md                 notable changes, newest first
TROUBLESHOOTING.md           every error hit during setup, and the fix
42sync_install.sh            installs everything below, plus rclone itself
                              (at the repo root, not bin/, so it's the
                              first thing visible from a fresh clone). Also
                              has configure-set/-reset/-show verbs, for
                              setting per-machine overrides before ever
                              installing anything -- see Configuration,
                              Reconfiguring a single machine
rclone-release-key.asc       rclone's release signing key -- read directly by
                              42sync_install.sh during its own rclone-download
                              check, never copied into ~/bin, so it stays at
                              the repo root next to the script that uses it
bin/                          deliberately laid out as a mirror of the installed
                              ~/bin -- everything here lands under ~/bin at the
                              same relative path. Only the flat 42* commands
                              sit at this top level; everything they depend
                              on but that isn't itself directly runnable
                              lives one level down, under 42-internal/
bin/42sync                    the sync wrapper (install to ~/bin)
bin/42projects                choose which projects sync to THIS machine (install to ~/bin)
bin/42links                   docs/ and repos/ shortcuts into ~ (install to ~/bin)
bin/42password                store the config password so it stops prompting (install to ~/bin)
bin/42logs                    list logs written by every 42* script (install to ~/bin)
bin/42-internal/lib/          shared config, the configure-set/-reset/-show
                              implementation, and bash tab-completion every
                              script sources, never run directly (install
                              to ~/bin/42-internal/lib)
bin/42-internal/defaults/     default content scripts copy into place on
                              first run: the filter file defaults,
                              READ-ME-FIRST.txt/.md (42sync seed/resync-apply
                              drop both into ~/Projects if they aren't there
                              yet -- one plain-text, one Markdown, so it
                              reads cleanly wherever it's opened from), and
                              42-common.local.sh (a commented-out template
                              for per-machine overrides -- see
                              Configuration, Reconfiguring a single
                              machine) (install to ~/bin/42-internal/defaults)
bin/42-internal/win/          Windows-specific helper code that isn't plain
                              data (the DPAPI password helper 42password
                              copies from -- see README, Known limitations)
                              (install to ~/bin/42-internal/win)
docs/                        GitHub Pages site (home / privacy / terms)
```

`docs/` exists only because Google requires a home page, privacy policy, and terms
of service URL on a real domain before an OAuth app can be published out of "Testing". It is served at
`https://<your-github-username>.github.io/rclone-42prague/`.

The contact address on those three pages is the original author's. Set your own
before publishing your fork's copy: `./docs/set-email.sh you@example.com` (or run
with no argument to be prompted) rewrites all three pages consistently. The
address is stored reversed, not plain text (`docs/email.js` decodes it client-side),
so a scraper reading the raw HTML doesn't find a usable one — the script computes
that obfuscated form for you.

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
| Remote path | `gdrive:_projects-sync-rclone` |
| bisync workdir | `~/.local/state/_projects-sync-rclone/bisync` (**not** the default `~/.cache/...`) |
| Logs | `~/.local/state/_projects-sync-rclone/logs/<script>-<verb>-<timestamp>.log`, newest per (script, verb) as `<script>-<verb>-last.log` |
| Filters | `~/.config/_projects-sync-rclone/filters/projects-filters.txt` |

### Reconfiguring a single machine

Every value in the table above is a default set once, for every machine, in
`bin/42-internal/lib/42-common.sh` — editing that file means editing the repo and
reinstalling, which changes it everywhere.

To change one on just this machine instead — without a future
`./42sync_install.sh apply` (run to pick up tool updates) ever reverting it —
use the `configure-set`/`configure-reset`/`configure-show` verbs, on
whichever of these two you have to hand:

```bash
# Before ever installing anything, from a clone of this repo:
./42sync_install.sh configure-set local-path /mnt/data/Projects
./42sync_install.sh configure-set keep-logs 50

# After installing, from anywhere -- no repo clone needed:
42sync configure-show      # print every setting's current effective value
42sync configure-reset local-path
```

`./42sync_install.sh`'s configure-* verbs work *before* ever installing
anything, not just after: run one first (e.g. `configure-set bin-path ...` to
install somewhere other than `~/bin`), and its very own first `apply` already
honors it.

Under the hood both just edit `~/.config/_projects-sync-rclone/42-common.local.sh`
— created once, commented out, the first time any `42*` script or the
installer runs. Editing that file by hand works exactly as well; these verbs
only save you finding the right line:

```bash
# ~/.config/_projects-sync-rclone/42-common.local.sh
LOCAL_PATH="/mnt/data/Projects"
KEEP_LOGS=50
```

It's sourced after every default above is set, so a plain reassignment is
enough to override it, and it's never version-controlled or touched again by
the installer once it exists.

### Windows: `~/Projects` living somewhere else

Setting `LOCAL_PATH` as above works on Windows too, but for that specific case a
junction is usually the better fix — it also makes File Explorer and every
other Windows tool see `~/Projects` at the real location, not just this
toolkit's own scripts. If your real projects folder lives elsewhere (a
different drive, say), point `~/Projects` at it with an NTFS **junction**,
not a symlink:

```powershell
New-Item -ItemType Junction -Path "C:\Users\<you>\Projects" -Target "D:\Projects"
```

A junction, not `ln -s`: Git Bash's `ln -s` creates an MSYS-only symlink that
native Windows binaries (rclone included) cannot follow — they'd see a small text
file instead of your actual folder. A junction is a real NTFS reparse point, so
both Git Bash and rclone resolve it transparently, in both directions, with no
special-casing anywhere else in this toolkit.

A junction also has a real limitation worth knowing before you rely on it:
`find` on Git Bash can intermittently fail to traverse into one at all (an
MSYS/NTFS reparse-point resolution quirk, not something this toolkit
controls) — `42sync` works around this internally, but if you ever write your
own commands against a junctioned `~/Projects`, pass `find -H` rather than
plain `find` to be safe.

### Windows: native Git Bash, or WSL?

Everything in this repo runs natively on Windows via Git for Windows' bash —
that's the simpler default, needs no extra install, and is what's documented
throughout. But native Windows has real limitations a Linux environment
doesn't. Hit directly while setting this up (the first three each have their
own TROUBLESHOOTING.md entry, linked there):

- Creating symlinks needs either elevation or a one-time Developer
  Mode/`secpol.msc` grant.
- A 42 Piscine exercise with a deliberately tricky filename (containing `"`,
  `*`, or `?`) **cannot be checked out at all** on NTFS — Windows' file APIs
  reject those characters unconditionally, no git setting works around it.
  The file exists in history and is viewable with `git show`, but never as an
  actual file on disk, on any native Windows filesystem. If its `.git` index
  entry ever gets corrupted, rebuilding the index the normal way fails on
  this exact path too — see TROUBLESHOOTING.md for the recovery.
- Renaming or removing a directory can fail with "Device or resource busy"
  if your own shell is sitting inside it, or another program (an editor, an
  indexer) has it open — Windows locks directories far more readily than
  Linux does.
- `find` on a junctioned `~/Projects` (see above) can intermittently fail to
  traverse into it at all — `42sync` already works around this in its own
  code (no TROUBLESHOOTING.md entry needed), but pass `find -H` yourself if
  you ever script against it directly.

Known general Windows/git friction not specifically hit by this toolkit, but
worth knowing about if you're deciding between native and WSL:

- NTFS is case-insensitive by default; two files differing only by case
  (unlikely, but possible in someone else's contribution) would collide on
  checkout.
- `core.autocrlf` commonly defaults to `true` on Windows vs. `false`/`input`
  on Linux/macOS — every text file can show as "modified" purely from
  line-ending conversion on a fresh cross-platform checkout.

If you hit any of these, or would just rather avoid them, [WSL
(Windows Subsystem for Linux)](https://learn.microsoft.com/windows/wsl/install)
gives you a real Linux filesystem (ext4) on the same machine:

```powershell
wsl --install
```

Needs a restart to finish, and its own one-time Linux username/password setup
on first launch. From inside WSL, clone your repos into WSL's *own* home
directory (e.g. `~/Projects`, not `/mnt/c/...` — that's still the same NTFS
volume under the hood, so it doesn't solve the filename problem) and run this
toolkit's install steps exactly as documented, just from the WSL shell
instead of Git Bash.

The WSL distro's virtual disk lives on `C:` by default
(`%LOCALAPPDATA%\Packages\<Distro>\LocalState\ext4.vhdx`) — if your real work
lives on another drive, you can relocate it:

```powershell
wsl --export Ubuntu ubuntu-backup.tar
wsl --unregister Ubuntu
wsl --import Ubuntu D:\WSL ubuntu-backup.tar
```

Native Git Bash and WSL both work — pick WSL only if you've actually hit one
of the issues above, or want to avoid them; otherwise native stays the
simpler choice.

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
`~/.local/state/_projects-sync-rclone/bisync`, which does persist across logouts.

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
# 1. Install rclone and every 42* script into ~/bin -- no root required
git clone https://github.com/<your-github-username>/rclone-42prague.git
cd rclone-42prague
# optional: ./42sync_install.sh configure-set bin-path ... to install somewhere
# other than ~/bin, or any other override -- see Configuration, Reconfiguring
# a single machine. Skip this if the defaults are fine.
./42sync_install.sh apply
exec zsh                      # pick up the new PATH (bash: pick up tab-completion too)

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
42links apply
```

`42sync_install.sh apply` ends by printing whichever of steps 2–5 still apply on this
machine, so you can tell what is left without re-reading this file. It downloads
rclone as a plain binary into `~/bin` (campus machines give you no admin rights), and
checks it against a SHA256 that has itself been PGP-verified against rclone's release
key before installing anything — see *Verifying the rclone download* under Security
notes. It deliberately stops short of `rclone config` and `42sync seed` — both need
decisions it should not make for you.

Re-run it any time to update the tools. It is idempotent: it only touches what has
actually changed, and `42sync_install.sh check` shows what it would do without doing
it. Run `./42sync_install.sh` with no arguments any time to see every verb it accepts.

Every run writes `~/.local/state/_projects-sync-rclone/logs/42sync_install-<mode>-<timestamp>.log` (see
*Logs* under Daily use). It keeps what the terminal does not: the exact URLs fetched,
`curl`'s own error text (it runs silent), the full gpg output, and — when a signature
or checksum check fails — the `SHA256SUMS` as received. That evidence would otherwise
die with the temp directory.

`42sync seed` refuses to run against a non-empty `~/Projects`. That is deliberate —
it exists to prevent a half-populated folder from being taken as the truth.

## Daily use

```bash
42sync apply           # two-way sync -- sitting down, and before leaving
42sync check           # dry run of apply, changes nothing
42sync verify          # compare real content: is everything local actually on Drive?
42sync status          # local size, remote size, last run
42sync force-check     # preview pushing a directory rename through the delete guard
42sync force-apply     # apply it for real (asks first, unless given the FORCE argument)
42sync orphans-check   # list excluded files stranded on Drive -- deletes nothing
42sync orphans-apply   # delete them for real (asks first, unless given DELETE)
42projects             # choose which projects sync to THIS machine (separate script)
42sync seed            # only when ~/Projects is empty (fresh account / other machine)
42sync resync-check    # only when ~/Projects already has content AND no baseline exists yet
42sync resync-apply    # (e.g. a laptop joining a Drive folder a campus machine already seeded)
```

Run any of `42sync`, `42links`, `42password`, `42sync_install.sh` or `42projects` with
no arguments to see the full verb list with descriptions — it prints and exits,
changing nothing and writing no log. In bash, after `42sync_install.sh apply` has run
once and you've opened a new shell, `<TAB>` after any script name completes its verbs.

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
42links apply         # create or refresh the links
42links check         # dry run, changes nothing
42links status        # show current state, including broken links
42links clean-check   # preview removing only the links pointing into 42Prague/
42links clean-apply   # remove them for real
```

Both scripts refuse to touch a real directory sitting where a link would go, and
`42links` refuses to run at all if a destination resolves inside `~/Projects` — a link
in there would be mirrored to Drive as a `.rclonelink` holding a per-machine path.

### Choosing what this machine carries

Not every project belongs on every machine. `~/Projects` is one folder on Drive, but a
laptop project does not need to land on a campus machine. This is `42projects`, a
separate script from `42sync` since it manages *what* syncs rather than doing the
sync itself.

**Default is excluded.** A fresh machine, or a project new to Drive this machine has
never seen, starts off — nothing pulls down until you explicitly include it. That is
deliberate: choosing what a given machine actually carries beats discovering it already
pulled down everything that ever existed on Drive.

```bash
42projects list                    # numbered table: what syncs here, and what does not
42projects diff    <ID>            # compare the two copies before deciding
42projects include <ID>            # carry it on this machine
42projects exclude <ID>            # stop carrying it here
```

`<ID>` can always be left out — every verb shows the current list and prompts for one
if you do:

```
  ID   STATUS    FOLDER                   WHERE
  1    synced    42Prague                 local + Drive
  2    excluded  MacApp                   local + Drive    both copies exist -> 42projects diff 2
  3    excluded  DriveOnly                Drive only
  4    stale     GhostFolder              -                rule matches nothing; drop it
```

IDs are assigned fresh each time `list` runs (stable ordering, but they can shift if
the folder set itself changes between runs) — to guard against acting on a
stale, memorized ID from an earlier listing, every ID-driven command echoes which
folder it resolved the ID to (`ID 2 -> MacApp`) as its first line of output, before
doing anything else.

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
42projects diff 2
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

The selection lives in `~/.config/_projects-sync-rclone/filters/projects-local.txt`, which is **per-machine and
never synced** — that is the whole point. It is deliberately a different file from the
artifact filters below, because `42sync orphans-check`/`orphans-apply` treat everything
the artifact filters exclude as junk on Drive and offer to delete it. A project you are
keeping on Drive on purpose must never appear in that list.

#### Deleting a folder from Drive

```bash
42projects exclude 2         # first: protect the local copy
42projects delete-check 2    # preview
42projects delete-apply 2    # then: remove it from Drive for real
```

The order matters, and the command enforces it. If a folder is **still syncing** and a
copy is on this machine, deleting it from Drive would make the next `42sync apply` read
that as "deleted on Path2" and remove your local copy too. `delete-check`/`delete-apply`
refuse in that case and tell you to exclude it first. Once excluded, the path is
filtered out and nothing propagates in either direction, so the local copy is safe.

`delete-apply` shows the object count and size, warns that this removes the folder **for
every machine**, runs a `--dry-run` purge, and (unless given the confirmation argument)
makes you type the folder name before doing anything for real. It is a terminal
command — no web interface involved. The exclusion works only because filters hide the
path from *sync*; `rclone purge` addresses the remote path directly and never reads them.

Afterwards the exclusion rule is left in place on purpose: with the folder gone from
Drive, that rule is now the only thing stopping the next sync from uploading your local
copy straight back up.

The one case that does need drive.google.com is a purge failing with
`appNotAuthorizedToChild` — that folder holds something rclone did not create, and under
the `drive.file` scope no rclone command can remove it.

Filters: `~/.config/_projects-sync-rclone/filters/projects-filters.txt` (artifact excludes: `*.o`, `*.out`,
caches, Claude Code's `.claude/` runtime state — shared intent on every machine,
created on first run, yours to edit)

### Logs

Every run of every script that does something writes its own log and prints the path
as its **last line**, whether it succeeded, failed or was aborted — with the
deliberate exception of purely informational invocations (`42projects list`, a bare
no-argument call, `42logs` itself), which write nothing: listing things would leave a
trail of entries that record nothing but having looked.

```
Log: /home/<login>/.local/state/_projects-sync-rclone/logs/42sync-verify-2026-08-31-142752.log
```

Every script writes to `~/.local/state/_projects-sync-rclone/logs/`, so there is one place to look. Logs
are named `<script>-<verb>-<timestamp>.log` — the script name stays in the filename
even though the verb you type is often short (`apply`, `check`) and shared across
scripts, so files from different scripts in the same directory never collide:

| Prefix | Written by |
|---|---|
| `42sync-<verb>-` | `42sync` |
| `42projects-<verb>-` | `42projects` (not `list`, which writes nothing) |
| `42links-<verb>-` | `42links` |
| `42password-<verb>-` | `42password` |
| `42sync_install-<verb>-` | `42sync_install.sh` |

`<script>-<verb>-last.log` symlinks to the most recent run of that exact
(script, verb) pair — e.g. `42sync-force-apply-last.log`,
`42sync_install-check-last.log` — so any one of them is directly discoverable without
hunting the whole directory. Each script prunes only its own prefixes, keeping the
newest 20 across all its verbs combined, so none can delete another's evidence.
`42logs` lists everything there, and writes nothing itself.

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
guard will abort. This is correct behaviour; run `42sync force-check` and confirm the
dry run shows matched delete/create pairs, then `42sync force-apply`. Reorganize
*before* a sync, not between syncs, when you can.

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
it. For unattended runs use `--password-command` pointing at a real secret store,
never `RCLONE_CONFIG_PASS` in a shell profile — a world-readable rc file is not
an improvement over a world-readable config.

`42password` sets this up: macOS Keychain via the `security` CLI, or on Linux
`secret-tool` (libsecret/GNOME Keyring — install `libsecret-tools`/`libsecret`
first if it's missing). It stores the password once, wires
`RCLONE_PASSWORD_COMMAND` into your shell rc, and verifies with a real,
harmless `rclone listremotes` that it actually works before declaring success.

```bash
42password apply       # set it up (or confirm it already is)
42password check       # dry run, changes nothing
42password reinstall   # re-store the password even if one is already saved (e.g. you changed it)
```

On Linux, `secret-tool` needs a keyring daemon (`gnome-keyring` or equivalent)
already unlocked in the session — normally true after a desktop login, not
guaranteed on every campus machine's setup. `42password` reports this plainly
if storing fails, rather than leaving you to guess why.

Worth doing on your own laptop, where you are the only one who can unlock the
session in the first place. Worth skipping on the shared campus machine: it moves
the barrier from "knows the config password" to "is logged into this account",
which is a real trade the moment more than one person can reach the session.

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

`42sync_install.sh` fetches a binary over the network and makes it executable, so it verifies
what it got before trusting it:

1. Downloads the versioned zip and its `SHA256SUMS`, which rclone publishes PGP-clearsigned.
2. Imports `rclone-release-key.asc` into a **throwaway keyring** — never your
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
`gpg`, or a missing or replaced key file — `42sync_install.sh apply` installs nothing and says why.
`42sync_install.sh check` tells you in advance whether this machine can verify.

Campus machines give you no admin rights, so if `gpg` really is absent you cannot
simply install it. To proceed anyway, accepting that only the SHA256 is checked — which
catches a corrupted download but not a tampered mirror — opt out explicitly:

```bash
INSTALL_ALLOW_UNSIGNED=1 ./42sync_install.sh apply
```

It has to be typed. That is the point: skipping verification should be a decision, not
something you fall into by running on a machine that happens to lack `gpg`.
