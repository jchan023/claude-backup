#!/bin/bash
# Backs up Claude Desktop's app state and the Claude Code CLI's state
# (~/.claude, including your memory files and MCP config) to your chosen
# backup location (a cloud-synced folder or any other target directory),
# keeping a small number of rotating dated snapshots.
# See README.md for setup via install.sh.
set -euo pipefail

DESKTOP_SRC="$HOME/Library/Application Support/Claude"
CLI_SRC="$HOME/.claude"
ROOT="${CLAUDE_BACKUP_DEST:-$HOME/Backups/ClaudeDesktop}"
LATEST="$ROOT/latest"
DESKTOP_LATEST="$LATEST/desktop"
CLI_LATEST="$LATEST/cli"
SNAPSHOTS="$ROOT/snapshots"
TODAY="$SNAPSHOTS/$(date '+%Y-%m-%d')"
LOG="$HOME/Library/Logs/claude-desktop-backup.log"
KEEP="${CLAUDE_BACKUP_KEEP:-3}"
MAX_LOG_LINES="${CLAUDE_BACKUP_LOG_MAX_LINES:-2000}"
NOTIFY="${CLAUDE_BACKUP_NOTIFY:-1}"
INCLUDE_CREDENTIALS="${CLAUDE_BACKUP_INCLUDE_CREDENTIALS:-1}"

notify() {
  local title="$1" message="$2"
  [ "$NOTIFY" = "1" ] || return 0
  # title/message are passed via env vars and read with `system attribute`
  # rather than spliced into the AppleScript source string. Snapshot
  # directory names (e.g. in the pruning warning below) aren't fully
  # trusted input — on a cloud-synced backup location, anyone who can
  # write into that folder controls those names — and string-splicing
  # them into `-e` would let a name containing a `"` break out of the
  # AppleScript string and run arbitrary commands via `do shell script`.
  CLAUDE_BACKUP_NOTIFY_TITLE="$title" CLAUDE_BACKUP_NOTIFY_MSG="$message" \
    /usr/bin/osascript -e 'display notification (system attribute "CLAUDE_BACKUP_NOTIFY_MSG") with title (system attribute "CLAUDE_BACKUP_NOTIFY_TITLE")' >/dev/null 2>&1 || true
}

trap 'notify "Claude Backup Failed" "Script exited with an error — check ~/Library/Logs/claude-desktop-backup.log"' ERR

mkdir -p "$DESKTOP_LATEST" "$CLI_LATEST" "$SNAPSHOTS" "$(dirname "$LOG")"

# claude_desktop_config.json, buddy-tokens.json, and config.json hold
# Desktop's auth/session credentials; mcp.json can hold API keys for MCP
# servers. CLAUDE_BACKUP_INCLUDE_CREDENTIALS=0 skips all of them — see
# README.md's Security section.
DESKTOP_INCLUDES=(--include="window-state.json" --include="git-worktrees.json" \
  --include="plan-usage-history.json" --include="cowork-enabled-cli-ops.json" \
  --include="claude-code-sessions/***" --include="local-agent-mode-sessions/***" \
  --include="*/" --exclude="*")
if [ "$INCLUDE_CREDENTIALS" = "1" ]; then
  DESKTOP_INCLUDES=(--include="claude_desktop_config.json" --include="config.json" \
    --include="buddy-tokens.json" "${DESKTOP_INCLUDES[@]}")
fi

rsync -a --delete --prune-empty-dirs \
  "${DESKTOP_INCLUDES[@]}" \
  "$DESKTOP_SRC/" "$DESKTOP_LATEST/" >> "$LOG" 2>&1

# ~/.claude is the Claude Code CLI's own state (MCP config, plugins,
# settings, session transcripts, and your memory files under
# projects/**/memory/) — small enough (tens of MB, not GBs) to mirror
# wholesale rather than allowlisting individual files like above.
if [ -d "$CLI_SRC" ]; then
  # A plain (unquoted, word-split) string rather than an array: macOS's
  # default /bin/bash is 3.2, where an *empty* array expanded with
  # "${ARR[@]}" under `set -u` throws "unbound variable" — this is the
  # credentials-included default, so it needs to actually work.
  CLI_EXCLUDES=""
  if [ "$INCLUDE_CREDENTIALS" != "1" ]; then
    CLI_EXCLUDES="--exclude=mcp.json --exclude=.credentials.json --exclude=credentials.json"
  fi
  # shellcheck disable=SC2086 # intentional word-splitting of a fixed, space-free flag list
  rsync -a --delete --prune-empty-dirs \
    $CLI_EXCLUDES \
    "$CLI_SRC/" "$CLI_LATEST/" >> "$LOG" 2>&1
fi

# Dated snapshot of today's backup (hardlinked, so it costs no extra space
# unless a file actually changed).
rm -rf "$TODAY"
cp -al "$LATEST" "$TODAY" 2>>"$LOG" || cp -a "$LATEST" "$TODAY" >> "$LOG" 2>&1

# Prune snapshots beyond the most recent $KEEP. On cloud-synced folders,
# rm -rf can race with the sync daemon holding a file handle and leave an
# empty directory behind, so retry once and verify before declaring success.
find "$SNAPSHOTS" -mindepth 1 -maxdepth 1 -type d | sort -r | tail -n +$((KEEP + 1)) | while read -r old; do
  # `|| true` on both attempts: under `set -e`, a genuinely failing
  # rm -rf here (this loop runs in a pipeline subshell) would abort the
  # whole script immediately via the generic ERR trap, before ever
  # reaching the retry/WARNING logic below that's specifically meant to
  # handle this case.
  rm -rf "$old" || true
  if [ -d "$old" ]; then
    sleep 2
    rm -rf "$old" || true
  fi
  if [ -d "$old" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: failed to fully remove $old (will retry next run)" >> "$LOG"
    notify "Claude Backup Warning" "Could not fully remove old snapshot $(basename "$old") — check the log."
  else
    echo "$(date '+%Y-%m-%d %H:%M:%S') pruned $old" >> "$LOG"
  fi
done

echo "$(date '+%Y-%m-%d %H:%M:%S') backup complete" >> "$LOG"

# Trim the log to the most recent $MAX_LOG_LINES lines so it doesn't grow
# unbounded.
if [ "$(wc -l < "$LOG")" -gt "$MAX_LOG_LINES" ]; then
  tail -n "$MAX_LOG_LINES" "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi
