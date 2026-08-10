# Contributing

This is a small personal-scale utility, but improvements are welcome.

## Reporting issues

Open a GitHub issue with your macOS version, what you ran, and the
relevant lines from `~/Library/Logs/claude-desktop-backup.log`.

## Making changes

1. Fork and clone the repo.
2. Edit `claude-desktop-backup.sh`, `install.sh`, `uninstall.sh`, or
   `restore.sh`.
3. Run [ShellCheck](https://www.shellcheck.net/) locally before opening a
   PR — CI runs it on every push/PR and will fail on warnings:
   ```bash
   brew install shellcheck
   shellcheck *.sh
   ```
4. Test against a throwaway `$HOME` rather than your real one, since the
   scripts write to `~/Library/Scripts`, `~/Library/LaunchAgents`, and
   `~/Library/Logs`:
   ```bash
   FAKE_HOME=$(mktemp -d)
   HOME="$FAKE_HOME" ./install.sh
   HOME="$FAKE_HOME" "$FAKE_HOME/Library/Scripts/claude-desktop-backup.sh"
   HOME="$FAKE_HOME" ./restore.sh -y
   HOME="$FAKE_HOME" ./uninstall.sh
   rm -rf "$FAKE_HOME"
   ```
   Run scripts under `/bin/bash` explicitly at least once, not just
   whatever `bash` resolves to in your shell — macOS ships bash 3.2 by
   default (Apple hasn't updated it since bash went GPLv3), which has
   real behavioral differences from a newer Homebrew bash (e.g. an empty
   array expanded with `"${ARR[@]}"` under `set -u` throws "unbound
   variable" in 3.2 but not in 4+). A change that passes `shellcheck` and
   works under your interactive shell can still break under the actual
   interpreter launchd and `install.sh` invoke.
5. Open a PR describing what changed and why.

## Scope

This project intentionally stays macOS + launchd specific. If you want
Linux/cron support, a PR is welcome as long as it doesn't complicate the
macOS path — separate scripts are fine.
