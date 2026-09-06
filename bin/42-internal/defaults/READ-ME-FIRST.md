# Managed by rclone — read this before you add, edit, or move anything

**What this is:** a personal two-way mirror of `~/Projects` across the 42
Prague campus machines and this owner's own laptop(s), kept in sync by
rclone bisync (tool: `rclone-42prague`, Drive app scope: `drive.file`).

You could be reading this from any of three places — it means the same
thing everywhere, but only one of them is safe to edit from:

| Where | Safe to edit? |
| --- | --- |
| Google Drive, web UI (drive.google.com) | Read only |
| A Google Drive folder mounted locally (Drive for desktop or similar), NOT via rclone | Read only |
| `~/Projects` on a machine with `rclone-42prague` installed | **Yes — here** |

## Why the first two are read only

The sync uses Google's `drive.file` scope: rclone can only see files it
created itself.

Anything added or changed through drive.google.com, or through a Drive
folder mounted some other way, is **invisible to rclone**. It will sit
here looking synced, and it will never reach `~/Projects` on any machine.
There is no error message. It just never arrives.

Files must enter through `~/Projects` on a synced machine:

```
put it in ~/Projects/...   then run:   42sync apply
```

## Also

- Do not rename or move folders here from the web UI or a mounted Drive
  folder. rclone tracks them by ID, but bisync compares paths, and it
  will read that rename as "deleted here, still there" on the next sync.
- Deleting things here **does** propagate — the next sync removes them
  from `~/Projects` on every machine too. That part works normally, from
  any of the three places.
- Git repos are mirrored whole, `.git` included. This is a convenience
  copy, **not** a git remote. Push to a real remote before you leave a
  machine.
- Never run `42sync` from two machines at the same time.
