# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.3.2] - 2026-08-11

### Security

- `restore.sh` didn't validate its date argument before using it to
  build a path (`$ROOT/snapshots/$FROM`). Confirmed with a working
  proof-of-concept: `./restore.sh "../../elsewhere"` restores from
  anywhere readable on the filesystem, not just `snapshots/`. Fixed by
  requiring the argument to match `YYYY-MM-DD` (the only format
  `claude-desktop-backup.sh` ever actually creates) before use.
- `install.sh` interpolated `CLAUDE_BACKUP_DEST` and other settings
  directly into the generated plist's XML without escaping. Confirmed a
  destination path containing `&`/`<`/`>` produces invalid XML, which
  makes `launchctl load` silently fail (it prints "Load failed" but
  still returns exit 0 — a known quirk) while the script still prints
  "Loaded launchd job..." — a false sense of security where you'd
  believe backups are scheduled when they aren't. Fixed by XML-escaping
  interpolated values, validating `CLAUDE_BACKUP_HOUR`/`MINUTE`/`KEEP`/
  `LOG_MAX_LINES`/`NOTIFY`/`INCLUDE_CREDENTIALS` are plain integers
  before use, and verifying the job is actually registered
  (`launchctl list`) after loading instead of trusting `load`'s own
  exit status.
- README **Troubleshooting**: added a caveat that granting Full Disk
  Access to `/bin/bash` (the fix in 1.3.1) is a broad, system-wide
  grant — every shell script that invokes `/bin/bash`, not just this
  one, inherits it.

## [1.3.1] - 2026-08-11

### Added

- README **Troubleshooting** section covering a real failure: backups
  to a `~/Library/CloudStorage/`-backed destination (several cloud-sync
  providers' top-level folders can resolve there) can start failing with
  `rsync: ... open: Operation not permitted` because the backup runs as
  a background `launchd` agent, which doesn't automatically inherit the
  Full Disk Access an interactive Terminal session has — even though
  running the identical command by hand works fine, which is what makes
  it look like it "randomly" breaks. Documents the Full Disk Access fix
  and how to verify it with `launchctl kickstart`.

## [1.3.0] - 2026-08-10

### Added

- `restore.sh` — automates what the README's Restore section previously
  described as manual `cp` commands. Restores from `latest/` by default
  or a specific `snapshots/YYYY-MM-DD/` (`./restore.sh 2026-08-09`),
  supports `--list` to see available dates, prompts for confirmation
  before overwriting `~/Library/Application Support/Claude/` and
  `~/.claude/` (skippable with `-y`/`--yes` for scripting), and refuses
  to run unattended without `-y` when there's no interactive terminal.
  The manual copy steps are kept in the README as a documented
  alternative for anyone who'd rather not run a script over freshly
  restored data.
- Verified end-to-end (both `latest/` and a dated snapshot, both
  credentials-included and credentials-excluded backups, the
  missing-backup and non-interactive guards) before release.

## [1.2.0] - 2026-08-10

### Added

- `CLAUDE_BACKUP_INCLUDE_CREDENTIALS` (default `1`) — set to `0` to skip
  all credential-bearing files entirely: `buddy-tokens.json`,
  `config.json`, `claude_desktop_config.json` (Desktop), and `mcp.json`
  (CLI). Settable at install time or changed later by re-running
  `install.sh`, same as the other options. Trade-off: after a restore
  you'll need to re-authenticate and re-enter MCP credentials by hand.
- README **Security** section: the backup is only as secure as the
  backup location's own account security (no encryption — it copies
  files as-is); cloud version history can outlive local cleanup after
  rotating a leaked token; a table of exactly which files are
  credential-bearing and why.

### Fixed

- The initial implementation of `CLAUDE_BACKUP_INCLUDE_CREDENTIALS`
  used a bash array (`CLI_EXCLUDES=()`) that's empty by default. macOS's
  default `/bin/bash` is 3.2 (Apple hasn't shipped a newer one since
  bash moved to GPLv3), where expanding an *empty* array with
  `"${ARR[@]}"` under `set -u` throws "unbound variable" — which is
  exactly the default, credentials-included case. Caught by testing
  explicitly under `/bin/bash` rather than a newer bash from Homebrew.
  Fixed by using a plain word-split string for that one variable instead
  of an array.

## [1.1.2] - 2026-08-10

### Security

- Fixed an AppleScript injection vulnerability in `notify()`: the
  snapshot-pruning warning interpolated `$(basename "$old")` — a
  directory name from the backup destination — directly into an
  `osascript -e` string. A directory name containing a `"` could break
  out of the AppleScript string and run arbitrary shell commands via
  `do shell script`, executed with the user's privileges. Confirmed
  exploitable with a proof-of-concept payload before fixing. Since the
  backup destination is typically a cloud-synced folder, the practical
  attack surface is anyone who can write into it — a compromised cloud
  account, a shared-folder collaborator, or another device sharing the
  same account. Fixed by passing title/message through environment
  variables and reading them with AppleScript's `system attribute`
  instead of string-splicing them into the script source; re-verified
  the same payload is now inert.
- Pinned CI's GitHub Actions (`actions/checkout`, `ludeeus/action-shellcheck`)
  to immutable commit SHAs instead of mutable tags, so a compromised or
  re-pointed upstream tag can't silently pull different code into CI.

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

[Unreleased]: https://github.com/jchan023/claude-backup/compare/v1.3.2...HEAD
[1.3.2]: https://github.com/jchan023/claude-backup/compare/v1.3.1...v1.3.2
[1.3.1]: https://github.com/jchan023/claude-backup/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/jchan023/claude-backup/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/jchan023/claude-backup/compare/v1.1.2...v1.2.0
[1.1.2]: https://github.com/jchan023/claude-backup/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/jchan023/claude-backup/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/jchan023/claude-backup/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/jchan023/claude-backup/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/jchan023/claude-backup/releases/tag/v1.0.0
