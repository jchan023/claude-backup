# claude-backup

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
