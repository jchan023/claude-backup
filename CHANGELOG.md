# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.5.5] - 2026-08-12

### Fixed

- **`tests/run.sh` could silently take down a real production
  `launchd` job.** `launchctl load`/`unload` resolve jobs by `Label`
  within the whole `gui/<uid>` domain, which isn't scoped by `$HOME` at
  all — only file paths are. Every test install used `install.sh`'s
  fixed default `Label` (`com.local.claude-desktop-backup`), so on a
  machine that also has the real thing installed under that same
  default label, running the test suite's uninstall test would unload
  the *real* job as a side effect, even though every file path involved
  was otherwise correctly confined to a fake `$HOME` — the test's own
  assertions (checking the fake-`$HOME` plist/script are gone) still
  passed, with no indication anything outside the sandbox had happened.
  Reproduced directly: registered a throwaway real job under that
  label, ran the suite, confirmed it vanished. Fixed by adding an
  optional `CLAUDE_BACKUP_PLIST_LABEL` override to `install.sh`/
  `uninstall.sh` (defaults to the same fixed label for real installs,
  unchanged) and having `tests/run.sh` export a label unique to that
  test run (`com.local.claude-backup-tests-$$`) for every install it
  creates — collision-proof by construction, not by convention.
  Reverified the same repro: the throwaway real job now survives a full
  test run.

  Reported in [#3](https://github.com/jchan023/claude-backup/issues/3).

## [1.5.4] - 2026-08-12

### Fixed

- **1.5.3's fix for #1 introduced its own regression.** The `cp -a`
  fallback added there can itself exit nonzero on the same class of
  `chflags` error (Box Drive reported this happening on both `cp -al`
  *and* the `cp -a` fallback, for symlinks under `~/.claude/skills/`)
  while still successfully copying everything else. Left unguarded,
  that nonzero exit under `set -e` aborted the whole script — silently
  skipping both the `backup complete` log line and snapshot pruning
  (which runs after this point). The actual file data landed correctly
  either way; only the script's own success reporting and pruning were
  affected. Fixed by guarding the fallback with `|| true` (matching how
  pruning's own `rm -rf` calls are already guarded, since v1.3.3), plus
  a safety net: if `$TODAY` still doesn't exist after the fallback
  (a *genuine* total failure, not just a benign per-file `chflags`
  error), log a `WARNING` and fire a notification instead of silently
  doing nothing.

  Box Drive's specific `chflags`-on-symlink failure for a full (non-hardlink)
  copy isn't reproducible on local APFS — confirmed directly: a
  `chflags uchg`'d file makes `cp -al` fail (same inode, can't re-flag
  something already immutable) but a fresh `cp -a` copy of it succeeds
  (the new file isn't immutable yet). Verified the actual guard logic
  instead with a mock `cp` on `PATH` that does a real copy and then
  deliberately exits 1 for the `-a` case — testing the real script's
  control flow independent of a filesystem quirk that can't be
  triggered here. Confirmed both new tests fail against the actual
  1.5.3 code and pass against the fix.

  Reported in [#2](https://github.com/jchan023/claude-backup/issues/2).

## [1.5.3] - 2026-08-12

### Fixed

- Snapshot creation could leave a stray nested
  `snapshots/YYYY-MM-DD/latest/{desktop,cli}/` one level deeper than
  intended, duplicating that day's backup inside itself. If `cp -al`
  failed partway through (reported on Box Drive, whose virtual
  filesystem rejects `chflags` on certain symlinks — e.g. skills
  installed as symlinks to external repos under `~/.claude/skills/`) it
  had already created `$TODAY` with partial content before erroring,
  and the `cp -a` fallback then copied `$LATEST` *into* that
  already-existing directory instead of replacing it — that's just how
  `cp` behaves when its destination already exists. Not
  data-destroying (the correctly-placed top-level `desktop/`/`cli/`
  data was still there too), but recurred on every run and wasted space
  silently. Fixed by `rm -rf`ing `$TODAY` again before the fallback
  attempt, so it starts clean instead of nesting into `cp -al`'s partial
  output. Added a regression test that extracts the actual
  snapshot-creation lines from the real script and runs them in
  isolation against a hand-built `$LATEST`/`$TODAY` with an
  immutable-flagged file forcing the same partial-failure condition —
  confirmed it reproduces the exact nested structure against the old
  code and stays clean against the fix.

  Reported in [#1](https://github.com/jchan023/claude-backup/issues/1).

## [1.5.2] - 2026-08-11

### Removed

- **Reverted the wrapper-app approach entirely — 1.5.1's fix was also
  flawed, for a different reason than 1.5.0's.** 1.5.1 correctly used a
  real compiled binary (via `osacompile`) so the *wrapper itself* got
  its own distinct TCC identity — verified at the time by checking the
  TCC database and seeing a genuine denied entry for it. What wasn't
  re-verified: this project's actual payload is a **bash script**
  (`claude-desktop-backup.sh`), and the wrapper's `do shell script`
  ultimately still execs that script via its own `#!/bin/bash` shebang.
  Once `/bin/bash` appears anywhere in the chain — even several layers
  down, invoked from inside a genuinely distinct compiled binary — Full
  Disk Access checks fall back to `/bin/bash`'s own pre-existing grant
  instead of the wrapper's. Confirmed directly: ran the actual backup
  script through the compiled wrapper against the real protected path,
  with a bundle identity that had never been granted anything — it
  succeeded, and no new TCC entry was created. Same practical result as
  1.5.0 (no real scoping), via a different mechanism.
- The 1.5.1 "proof" (a bare `ls` command run through the same wrapper
  correctly got denied and created a real TCC entry) was real but not
  representative — `ls` never routes through `/bin/bash`, so it never
  exercised the actual failure mode. Confirmed that specifically: the
  same `ls` command wrapped in `/bin/bash -c "..."` instead reverts to
  the exact same silent-success-via-/bin/bash's-grant behavior.
- **Conclusion:** genuinely scoping Full Disk Access away from
  `/bin/bash` isn't achievable for a tool whose actual file-copy logic
  is a bash script shelling out to `rsync`/`cp`, without rewriting that
  logic in a compiled language instead — a much bigger undertaking than
  a wrapper, and out of scope here. Reverted `install.sh`/`uninstall.sh`
  to the pre-wrapper state (plain `/bin/bash` in `ProgramArguments`,
  everything else from 1.4.0–1.5.0 kept: XML escaping, integer
  validation, actual-registration verification, the credentials toggle,
  etc.), removed the wrapper-specific test assertions, and rewrote the
  README's Full Disk Access Troubleshooting entry to document what was
  tried, why it doesn't work, and that granting `/bin/bash` directly —
  a broad, system-wide grant — is the real, working fix. If you
  installed 1.5.0 or 1.5.1, re-run `install.sh` to remove the wrapper
  and revert your `launchd` job to invoking `/bin/bash` directly.

## [1.5.1] - 2026-08-11

### Fixed

- **1.5.0's wrapper app didn't actually scope anything — confirmed by
  checking the TCC database directly.** `Contents/MacOS/claude-desktop-backup`
  was the backup script itself with its `#!/bin/bash` shebang. A
  bundle's `CFBundleExecutable` naming that file doesn't change what the
  kernel actually runs: it still execve's `/bin/bash` as the top-level
  process (that's what a shebang *is*), and Full Disk Access is checked
  against whatever process is actually performing the file I/O — not
  against the bundle nominally wrapping it. Queried
  `/Library/Application Support/com.apple.TCC/TCC.db` directly after a
  real run: no entry existed for the wrapper's bundle identifier at all,
  and the backup succeeded anyway — proving it was silently still
  riding on the pre-existing `/bin/bash` grant the whole time. 1.5.0
  shipped no real improvement over granting `/bin/bash` directly.
- Fixed by generating the wrapper with `osacompile` (ships with macOS,
  no Xcode needed) instead of hand-building the bundle: its
  `Contents/MacOS/applet` is a genuine compiled Mach-O binary. Verified
  the fix the same way the bug was found — checked the TCC database
  after a real run against the actual protected path and got a new,
  distinct, *denied* entry for the app's bundle identifier (`auth_value=0`),
  proving TCC now evaluates it as its own identity instead of falling
  through to `/bin/bash`. Also verified `do shell script` (what the
  compiled applet uses to invoke the actual backup script) correctly
  forwards environment variables from `launchd`'s `EnvironmentVariables`
  through to the script, since the whole `CLAUDE_BACKUP_DEST` mechanism
  depends on that.
- `tests/run.sh` gained a permanent regression guard for the actual root
  cause: asserts the wrapper's executable is reported as `Mach-O` by
  `file`, not a script — the exact thing that silently failed in 1.5.0
  despite passing every other check at the time (bundle validity,
  codesign, launchd wiring, and even a real end-to-end run all looked
  fine; only inspecting the TCC database directly revealed the flaw).

If you installed 1.5.0, re-run `install.sh` to rebuild the wrapper
properly, then grant Full Disk Access to
`~/Library/Application Support/ClaudeBackup.app` again (the identity
changed, so any grant made against the 1.5.0 bundle isn't meaningful —
it was never being checked in the first place).

## [1.5.0] - 2026-08-11

### Added

- `install.sh` now wraps the backup script in a minimal, ad-hoc-signed
  `~/Library/Application Support/ClaudeBackup.app` bundle and points the
  launchd job at it, instead of at `/bin/bash` directly. This scopes the
  Full Disk Access grant needed for CloudStorage-backed destinations
  (see 1.3.1's Troubleshooting entry) to just this one app — previously
  granting `/bin/bash` Full Disk Access meant every other shell script
  on the machine that happens to invoke `/bin/bash` inherited it too.
  Doesn't eliminate the need for a per-machine grant (TCC permissions
  are never transferable between machines, by Apple's design — no
  configuration avoids that), only narrows what it covers. `uninstall.sh`
  removes the wrapper app too.
- `tests/run.sh` gained coverage for the wrapper: bundle/Info.plist
  validity, the code signature passing `codesign --verify`, the launchd
  job actually pointing at the wrapper instead of `/bin/bash`, and a
  real end-to-end run through the wrapper's executable producing correct
  output.

### Fixed

- Two more bugs caught writing the new tests: `plutil -extract ... raw`
  on an array value just prints its element count, not the content —
  fixed by extracting `xml1` instead and matching against that. And
  `launchctl kickstart` on an already-registered job always uses the
  real launchd-provided `$HOME` for the invoked process, not whatever
  `$HOME` override was exported in the shell that ran `install.sh` —
  discovered when a manual verification pass using a fake `$HOME` still
  read real `~/Library/Application Support/Claude` and real `~/.claude`
  content (though only their filenames were ever visible in output, and
  the fake destination was deleted immediately after). No code fix
  needed here — this is real `launchd` behavior, not a bug in the
  scripts — but worth knowing before using `kickstart` to test against a
  fake `$HOME`: it doesn't actually isolate the source paths, only
  whatever's explicitly baked into the plist's `EnvironmentVariables`
  (like `CLAUDE_BACKUP_DEST`).

## [1.4.0] - 2026-08-11

### Added

- `tests/run.sh` — a lightweight functional test suite (plain bash
  assertions, no framework) covering `install.sh`, `claude-desktop-backup.sh`,
  `restore.sh`, and `uninstall.sh`: plist validity and actual launchd
  registration (not just a claimed success), rejecting non-integer
  settings, XML-escaping, both credential modes, snapshot pruning
  keeping exactly `KEEP` entries, `restore.sh --list`/`latest`/dated
  restore with byte-identical content, the path-traversal guard, and
  `uninstall.sh` actually deregistering the job while preserving
  backups. Every one of these was previously verified by hand, ad hoc,
  in conversation — none of it was captured anywhere a future change
  could break without someone noticing.
- CI: renamed the workflow from `shellcheck.yml` to `ci.yml` (badge
  updated) and added a `test` job on `macos-latest` running
  `tests/run.sh` — `launchctl`/`osascript`/real bash 3.2 behavior can't
  be exercised on the existing Linux `shellcheck` job.

### Fixed

- Two bugs in the test suite itself, caught while writing it: piping
  `restore.sh --list`'s multi-line output live into `grep -q` is
  timing-dependent — `grep -q` exits after its first match and closes
  the pipe, which can SIGPIPE a still-writing upstream process. Fixed by
  capturing output into a variable first. Also an assertion assumed
  `launchctl list` returns exit code `1` for "job not found"; on this
  system it returns `113`. Fixed by checking for any non-zero exit
  instead of a specific code.

## [1.3.3] - 2026-08-11

### Fixed

- Snapshot pruning's retry/`WARNING` logic (added in 1.0.1, hardened
  further since) was unreachable whenever `rm -rf` actually failed. That
  loop runs inside a pipeline subshell, so under `set -e` a failing
  `rm -rf` aborted the whole script immediately via the generic ERR trap
  — before ever reaching the `if [ -d "$old" ]` retry/log logic meant to
  handle exactly that case. Only surfaced now because earlier tests of
  that path (`chflags`/`chmod` tricks meant to force a real removal
  failure) happened not to actually block `rm -rf` in whatever sandbox
  they ran in — this time one did, and the bug showed up as an
  unexpected non-zero exit instead of the intended `WARNING` log line.
  Fixed with `|| true` on both `rm -rf` attempts so a real failure falls
  through to the retry/warning logic instead of killing the script.
  Reverified: with `CLAUDE_BACKUP_NOTIFY=1` a real notification fires on
  the forced failure (confirmed visually); with `=0` it's suppressed;
  either way the script now reaches `backup complete` instead of exiting
  early.

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

[Unreleased]: https://github.com/jchan023/claude-backup/compare/v1.5.5...HEAD
[1.5.5]: https://github.com/jchan023/claude-backup/compare/v1.5.4...v1.5.5
[1.5.4]: https://github.com/jchan023/claude-backup/compare/v1.5.3...v1.5.4
[1.5.3]: https://github.com/jchan023/claude-backup/compare/v1.5.2...v1.5.3
[1.5.2]: https://github.com/jchan023/claude-backup/compare/v1.5.1...v1.5.2
[1.5.1]: https://github.com/jchan023/claude-backup/compare/v1.5.0...v1.5.1
[1.5.0]: https://github.com/jchan023/claude-backup/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/jchan023/claude-backup/compare/v1.3.3...v1.4.0
[1.3.3]: https://github.com/jchan023/claude-backup/compare/v1.3.2...v1.3.3
[1.3.2]: https://github.com/jchan023/claude-backup/compare/v1.3.1...v1.3.2
[1.3.1]: https://github.com/jchan023/claude-backup/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/jchan023/claude-backup/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/jchan023/claude-backup/compare/v1.1.2...v1.2.0
[1.1.2]: https://github.com/jchan023/claude-backup/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/jchan023/claude-backup/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/jchan023/claude-backup/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/jchan023/claude-backup/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/jchan023/claude-backup/releases/tag/v1.0.0
