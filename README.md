# claude-backup

[![ShellCheck](https://github.com/jchan023/claude-backup/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/jchan023/claude-backup/actions/workflows/shellcheck.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Daily backup of Claude Desktop's config, auth tokens, and session history
(macOS) to Dropbox or any other target directory, using `launchd`.

It backs up:

- `claude_desktop_config.json`, `config.json`, `buddy-tokens.json` — app
  config and auth/session tokens (lets you skip re-logging-in after a
  restore)
- `window-state.json`, `git-worktrees.json`, `plan-usage-history.json`,
  `cowork-enabled-cli-ops.json` — settings
- `claude-code-sessions/`, `local-agent-mode-sessions/` — conversation and
  session history

It deliberately **excludes** `Cache/`, `Code Cache/`, `GPUCache/`,
`IndexedDB/`, `Local Storage/`, and similar browser-cache directories —
these regenerate automatically and just waste space (Claude Desktop's data
directory is a Chromium/Electron profile, so most of its multi-GB footprint
is disposable cache).

Keeps a `latest/` mirror plus a small number of dated snapshots so you can
recover from an accidental overwrite, not just the most recent state — see
[Snapshot pruning](#snapshot-pruning) for how that works.

Since the tokens file contains auth/session credentials, only use this if
you're comfortable with that material living in your backup destination
(e.g. your own private Dropbox).

## Install

```bash
git clone https://github.com/jchan023/claude-backup.git
cd claude-backup
./install.sh
```

By default this backs up to `~/Dropbox/Backups/ClaudeDesktop` and runs
daily at 9:00 AM. Override with environment variables before running
`install.sh`:

```bash
CLAUDE_BACKUP_DEST="$HOME/Dropbox/Backups/ClaudeDesktop" \
CLAUDE_BACKUP_KEEP=3 \
CLAUDE_BACKUP_HOUR=9 \
CLAUDE_BACKUP_MINUTE=0 \
./install.sh
```

- `CLAUDE_BACKUP_DEST` — where backups are written (must be set at run
  time too, e.g. in your shell profile, since it's read by the backup
  script itself, not just the installer)
- `CLAUDE_BACKUP_KEEP` — number of dated snapshots to retain
- `CLAUDE_BACKUP_HOUR` / `CLAUDE_BACKUP_MINUTE` — daily run time (24h)

## Backing up somewhere other than Dropbox

Point `CLAUDE_BACKUP_DEST` at any locally-synced folder — Google Drive,
OneDrive, iCloud Drive, an external drive, etc. — and it just works, no
code changes needed:

```bash
CLAUDE_BACKUP_DEST="$HOME/Library/CloudStorage/GoogleDrive-you@gmail.com/My Drive/Backups/ClaudeDesktop" \
./install.sh
```

Two things to know:

- **This backs up to a local path that some other process syncs to the
  cloud** (Dropbox/Google Drive/OneDrive's desktop app), not directly to a
  cloud API. If you use Google Drive in "Stream" mode, its mount point is
  usually under `~/Library/CloudStorage/GoogleDrive-<account>/My Drive`.
- **Hardlinked snapshots need a real filesystem.** Some cloud-sync mounts
  (notably Google Drive Stream, and some network mounts) don't support
  hardlinks. The script already handles this — `cp -al` (hardlink) is
  tried first and falls back to a full `cp -a` copy automatically — but on
  those destinations each snapshot uses real extra disk space instead of
  being nearly free.

`CLAUDE_BACKUP_DEST` must be set when you run `install.sh`, not just
exported in your shell — launchd doesn't inherit your terminal's
environment, so `install.sh` bakes it into the launchd job's
`EnvironmentVariables` at install time. To change the destination later,
just re-run `install.sh` with the new value.

## Snapshot pruning

Every run does two things after syncing `latest/`:

1. Copies `latest/` into a dated snapshot, `snapshots/YYYY-MM-DD/`. If the
   script runs more than once on the same day, that day's snapshot is just
   overwritten — you get one snapshot per calendar day, not per run.
2. Deletes snapshots beyond the newest `CLAUDE_BACKUP_KEEP` (default `3`),
   picking the newest by sorting directory names — which works because
   `YYYY-MM-DD` sorts chronologically as plain text.

Snapshots are created with hardlinks (`cp -al`) against `latest/` rather
than full copies, so keeping N days of history costs close to zero extra
disk space — each snapshot only takes real space for files that changed
since the previous one. On filesystems that don't support hardlinks (e.g.
Google Drive Stream — see above), it falls back to a full copy per
snapshot instead.

Because the destination is typically a cloud-sync folder, deleting a
snapshot directory can race with the sync daemon (Dropbox, Google Drive,
etc.) holding a file handle open, which can leave an empty
directory behind instead of fully removing it. The script retries the
delete once after a short pause and verifies the directory is actually
gone; if it still can't remove it, it logs a `WARNING` line instead of
falsely claiming success, and cleans it up on the next run. Check
`~/Library/Logs/claude-desktop-backup.log` if `snapshots/` ever seems to
hold more than `CLAUDE_BACKUP_KEEP` entries.

To change how many snapshots are kept, re-run `install.sh` with a new
`CLAUDE_BACKUP_KEEP`:

```bash
CLAUDE_BACKUP_KEEP=7 ./install.sh
```

## Usage examples

Run a backup manually (useful right after install, or to test a config
change) instead of waiting for the next scheduled run:

```bash
~/Library/Scripts/claude-desktop-backup.sh
```

Tail the log to confirm it's running and see what got pruned:

```bash
tail -f ~/Library/Logs/claude-desktop-backup.log
```

List available snapshots to restore from:

```bash
ls ~/Dropbox/Backups/ClaudeDesktop/snapshots
```

Change the schedule to 6:30 PM and keep 7 days of history instead of the
defaults:

```bash
CLAUDE_BACKUP_HOUR=18 CLAUDE_BACKUP_MINUTE=30 CLAUDE_BACKUP_KEEP=7 ./install.sh
```

## Restore

1. Install Claude Desktop and quit it.
2. Copy files from your backup's `latest/` (or a specific
   `snapshots/YYYY-MM-DD/`) into `~/Library/Application Support/Claude/`.
3. Relaunch Claude Desktop.

## Uninstall

```bash
./uninstall.sh
```

Removes the launchd job and installed script. Existing backup files are
left untouched.

## Logs

`~/Library/Logs/claude-desktop-backup.log`
