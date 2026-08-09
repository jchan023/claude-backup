# Contributing

This is a small personal-scale utility, but improvements are welcome.

## Reporting issues

Open a GitHub issue with your macOS version, what you ran, and the
relevant lines from `~/Library/Logs/claude-desktop-backup.log`.

## Making changes

1. Fork and clone the repo.
2. Edit `claude-desktop-backup.sh`, `install.sh`, or `uninstall.sh`.
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
   HOME="$FAKE_HOME" ./uninstall.sh
   rm -rf "$FAKE_HOME"
   ```
5. Open a PR describing what changed and why.

## Scope

This project intentionally stays macOS + launchd specific. If you want
Linux/cron support, a PR is welcome as long as it doesn't complicate the
macOS path — separate scripts are fine.
