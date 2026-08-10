# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.1.1] - 2026-08-10

### Fixed

- `local-agent-mode-sessions/skills-plugin/` is no longer excluded from
  the Desktop backup. It was excluded on the assumption Claude Desktop
  re-syncs this app-managed content automatically — a reasonable
  inference (it's identified as "Anthropic-managed skills for Claude
  Desktop" and tracked by a `remote_marketplace_migration_done_v1` flag
  in `config.json`) but never actually verified against a real restore,
  since there was no safe way to test it without risking the live app.
  At ~4MB, backing it up is cheap enough that the assumption isn't worth
  the risk.

## [1.1.0] - 2026-08-09

### Added

- Back up `~/.claude` (the Claude Code CLI's own state) in addition to
  Claude Desktop's app state. Previously the backup only covered
  `~/Library/Application Support/Claude`, which meant `mcp.json`,
  installed plugins, CLI settings, session transcripts, and — most
  importantly — the entire memory system under `projects/**/memory/` were
  never backed up at all. Mirrored wholesale (no allowlist) since it's
  small (tens of MB vs. Desktop's multi-GB profile).

### Changed

- **Backup layout**: `latest/` and each dated `snapshots/YYYY-MM-DD/` now
  contain two subdirectories, `desktop/` and `cli/`, instead of Desktop's
  files sitting directly at the top level. Existing backups written by
  older versions are not migrated automatically — see
  [Restore](README.md#restore) for the current layout.

## [1.0.1] - 2026-08-09

### Fixed

- `~/Library/Logs` is no longer assumed to exist — `install.sh` and
  `claude-desktop-backup.sh` now `mkdir -p` it before writing the log.
  On a genuinely fresh `$HOME` with no pre-existing `Logs` directory
  (verified by testing the README's install instructions against a
  clean clone), the very first log write failed and aborted the backup.

## [1.0.0] - 2026-08-09

Initial release.

### Added

- Daily backup of Claude Desktop's config, auth tokens, and session
  history via `launchd`, installed with `install.sh`.
- Dated snapshot retention (`snapshots/YYYY-MM-DD/`, hardlinked against
  `latest/`) with configurable retention via `CLAUDE_BACKUP_KEEP`.
- Log rotation — trims `~/Library/Logs/claude-desktop-backup.log` to the
  most recent `CLAUDE_BACKUP_LOG_MAX_LINES` lines (default 2000) after
  every run.
- macOS notifications on backup failure or snapshot-pruning warnings,
  toggleable with `CLAUDE_BACKUP_NOTIFY`.
- `uninstall.sh` to remove the launchd job and installed script.
- ShellCheck CI workflow, MIT license, README usage examples and table of
  contents, a terminal usage demo (`assets/demo.svg`), and a
  `CONTRIBUTING.md` guide.

### Changed

- Generalized backup-location terminology throughout — no longer assumes
  any specific provider; the default `CLAUDE_BACKUP_DEST` is now
  `~/Backups/ClaudeDesktop`, with cloud sync (Google Drive, OneDrive,
  iCloud Drive, or similar) achieved by pointing it at whichever
  provider's synced folder you prefer.
- Bumped `actions/checkout` to v5 to resolve a Node 20 deprecation warning
  in CI.

### Fixed

- `install.sh` now bakes `CLAUDE_BACKUP_DEST` and `CLAUDE_BACKUP_KEEP`
  into the launchd job's `EnvironmentVariables`; previously they were
  only read at install time and silently lost at run time, since launchd
  doesn't inherit the installing shell's environment.
- Snapshot pruning now retries and verifies deletion instead of blindly
  logging success — cloud-sync daemons can race with `rm -rf` and leave
  an empty directory behind.
- ShellCheck SC2012: replaced `ls` with `find` when listing snapshot
  directories for pruning, to handle filenames more robustly.

[Unreleased]: https://github.com/jchan023/claude-backup/compare/v1.1.1...HEAD
[1.1.1]: https://github.com/jchan023/claude-backup/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/jchan023/claude-backup/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/jchan023/claude-backup/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/jchan023/claude-backup/releases/tag/v1.0.0
