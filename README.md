# claude-backup

[![Release](https://img.shields.io/github/v/release/jchan023/claude-backup)](https://github.com/jchan023/claude-backup/releases/tag/v1.1.1)
[![ShellCheck](https://github.com/jchan023/claude-backup/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/jchan023/claude-backup/actions/workflows/shellcheck.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Assets License: MIT](https://img.shields.io/badge/Assets-MIT-blue.svg)](LICENSE)

Daily backup of both **Claude Desktop's** app state and the **Claude
Code CLI's** state (macOS) to your backup location of choice, using
`launchd`.

![Usage demo](assets/demo.svg)

It backs up two sources, into `latest/desktop/` and `latest/cli/`
respectively:

**Claude Desktop** (`~/Library/Application Support/Claude`):

- `claude_desktop_config.json`, `config.json`, `buddy-tokens.json` — app
  config and auth/session tokens (lets you skip re-logging-in after a
  restore)
- `window-state.json`, `git-worktrees.json`, `plan-usage-history.json`,
  `cowork-enabled-cli-ops.json` — settings
- `claude-code-sessions/`, `local-agent-mode-sessions/` — conversation and
  session history

It deliberately **excludes** `Cache/`, `Code Cache/`, `GPUCache/`,
`IndexedDB/`, `Local Storage/`, and similar browser-cache directories from
this source — they regenerate automatically and just waste space (Claude
Desktop's data directory is a Chromium/Electron profile, so most of its
multi-GB footprint is disposable cache).

`local-agent-mode-sessions/skills-plugin/` (Anthropic's built-in skill
implementations, e.g. `xlsx`/`pdf`/`docx`) **is** backed up, even though
it's app-managed content that the app likely re-syncs on its own —
everything points that way (`.claude-plugin/plugin.json` identifies it as
"Anthropic-managed skills for Claude Desktop", and `config.json` tracks a
`remote_marketplace_migration_done_v1` flag), but that's inference, not a
verified guarantee, and there was no safe way to test it against a real
install without risking the live app. At ~4MB it's cheap enough to just
include rather than gamble on it.

**Claude Code CLI** (`~/.claude`) — mirrored wholesale, no allowlist,
since it's small (tens of MB, not GBs):

- `settings.json` — CLI settings
- `mcp.json` — your MCP server definitions
- `plugins/installed_plugins.json`, `plugins/known_marketplaces.json` —
  installed plugins and marketplaces
- `projects/` — Claude Code session transcripts **and your memory system**
  (`projects/**/memory/MEMORY.md` and every individual memory file)

Keeps a `latest/` mirror plus a small number of dated snapshots so you can
recover from an accidental overwrite, not just the most recent state — see
[Snapshot pruning](#snapshot-pruning) for how that works.

Since the Desktop tokens file and `mcp.json` can both contain auth
credentials, only use this if you're comfortable with that material living
in your backup location (e.g. your own private cloud storage).

## Contents

- [Install](#install)
- [Choosing a backup location](#choosing-a-backup-location)
- [Snapshot pruning](#snapshot-pruning)
- [Usage examples](#usage-examples)
- [Restore](#restore)
- [Uninstall](#uninstall)
- [Logs](#logs)
- [Failure alerts](#failure-alerts)
- [Changelog](CHANGELOG.md)

## Install

```bash
git clone https://github.com/jchan023/claude-backup.git
cd claude-backup
./install.sh
```

By default this backs up to `~/Backups/ClaudeDesktop` and runs daily at
9:00 AM. Override with environment variables before running `install.sh`:

```bash
CLAUDE_BACKUP_DEST="$HOME/Backups/ClaudeDesktop" \
CLAUDE_BACKUP_KEEP=3 \
CLAUDE_BACKUP_HOUR=9 \
CLAUDE_BACKUP_MINUTE=0 \
./install.sh
```

- `CLAUDE_BACKUP_DEST` — your backup location, where backups are written
  (must be set at run time too, e.g. in your shell profile, since it's
  read by the backup script itself, not just the installer)
- `CLAUDE_BACKUP_KEEP` — number of dated snapshots to retain
- `CLAUDE_BACKUP_HOUR` / `CLAUDE_BACKUP_MINUTE` — daily run time (24h)

## Choosing a backup location

`CLAUDE_BACKUP_DEST` can point anywhere: a plain local folder, an external
drive, or — for offsite/cloud backup — the local folder that your cloud
sync app (Google Drive, OneDrive, iCloud Drive, or similar) keeps synced.
No code changes needed either way:

```bash
CLAUDE_BACKUP_DEST="$HOME/Library/CloudStorage/GoogleDrive-you@gmail.com/My Drive/Backups/ClaudeDesktop" \
./install.sh
```

Two things to know if your backup location is a cloud-synced folder:

- **This backs up to a local path that some other process syncs to the
  cloud**, not directly to a cloud API. If you use Google Drive in
  "Stream" mode, its mount point is usually under
  `~/Library/CloudStorage/GoogleDrive-<account>/My Drive`.
- **Hardlinked snapshots need a real filesystem.** Some cloud-sync mounts
  (notably Google Drive Stream, and some network mounts) don't support
  hardlinks. The script already handles this — `cp -al` (hardlink) is
  tried first and falls back to a full `cp -a` copy automatically — but on
  those destinations each snapshot uses real extra disk space instead of
  being nearly free.

`CLAUDE_BACKUP_DEST` must be set when you run `install.sh`, not just
exported in your shell — launchd doesn't inherit your terminal's
environment, so `install.sh` bakes it into the launchd job's
`EnvironmentVariables` at install time. To change the backup location
later, just re-run `install.sh` with the new value.

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

If your backup location is a cloud-synced folder, deleting a snapshot
directory can race with the sync daemon holding a file handle open, which
can leave an empty directory behind instead of fully removing it. The
script retries the delete once after a short pause and verifies the
directory is actually gone; if it still can't remove it, it logs a
`WARNING` line instead of falsely claiming success, and cleans it up on
the next run. Check `~/Library/Logs/claude-desktop-backup.log` if
`snapshots/` ever seems to hold more than `CLAUDE_BACKUP_KEEP` entries.

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
ls ~/Backups/ClaudeDesktop/snapshots
```

Check that both sources are actually being captured:

```bash
ls ~/Backups/ClaudeDesktop/latest/desktop ~/Backups/ClaudeDesktop/latest/cli
```

Change the schedule to 6:30 PM and keep 7 days of history instead of the
defaults:

```bash
CLAUDE_BACKUP_HOUR=18 CLAUDE_BACKUP_MINUTE=30 CLAUDE_BACKUP_KEEP=7 ./install.sh
```

## Restore

1. Install Claude Desktop and the Claude Code CLI, and quit/exit both.
2. Copy files from your backup's `latest/desktop/` (or a specific
   `snapshots/YYYY-MM-DD/desktop/`) into
   `~/Library/Application Support/Claude/`.
3. Copy files from `latest/cli/` (or the matching `snapshots/.../cli/`)
   into `~/.claude/`.
4. Relaunch Claude Desktop / the CLI.

## Uninstall

```bash
./uninstall.sh
```

Removes the launchd job and installed script. Existing backup files are
left untouched.

## Logs

`~/Library/Logs/claude-desktop-backup.log`

Trimmed to the most recent `CLAUDE_BACKUP_LOG_MAX_LINES` lines (default
`2000`, roughly years of daily runs since each run only logs a few lines)
after every run, so it doesn't grow unbounded. You can also grep it
directly for `WARNING` entries (non-fatal snapshot-pruning issues):

```bash
grep WARNING ~/Library/Logs/claude-desktop-backup.log
```

## Failure alerts

A macOS notification (via `osascript`) fires when:

- the script exits with an error (e.g. `rsync` fails) — "Claude Backup
  Failed"
- a snapshot can't be fully removed during pruning — "Claude Backup
  Warning" (see [Snapshot pruning](#snapshot-pruning))

Disable notifications with `CLAUDE_BACKUP_NOTIFY=0` (same caveat as the
other settings — set it when running `install.sh`, not just in your
shell, since launchd doesn't inherit your terminal's environment):

```bash
CLAUDE_BACKUP_NOTIFY=0 ./install.sh
```

Notifications appear from "Script Editor" in Notification Center — if
they don't show up, check System Settings → Notifications → Script
Editor.
