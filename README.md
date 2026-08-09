# claude-backup

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

Keeps a `latest/` mirror plus a small number of dated snapshots
(`snapshots/YYYY-MM-DD/`, default 3) so you can recover from an accidental
overwrite, not just the most recent state. Snapshots are hardlinked against
`latest/`, so they cost near-zero extra disk space unless a file actually
changed day to day.

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
