#!/bin/bash
# Backs up Claude Desktop's config, auth tokens, and session history to
# your chosen backup location (a cloud-synced folder or any other target
# directory), keeping a small number of rotating dated snapshots.
# See README.md for setup via install.sh.
set -euo pipefail

SRC="$HOME/Library/Application Support/Claude"
ROOT="${CLAUDE_BACKUP_DEST:-$HOME/Backups/ClaudeDesktop}"
LATEST="$ROOT/latest"
SNAPSHOTS="$ROOT/snapshots"
TODAY="$SNAPSHOTS/$(date '+%Y-%m-%d')"
LOG="$HOME/Library/Logs/claude-desktop-backup.log"
KEEP="${CLAUDE_BACKUP_KEEP:-3}"
MAX_LOG_LINES="${CLAUDE_BACKUP_LOG_MAX_LINES:-2000}"
NOTIFY="${CLAUDE_BACKUP_NOTIFY:-1}"

notify() {
  local title="$1" message="$2"
  [ "$NOTIFY" = "1" ] || return 0
  /usr/bin/osascript -e "display notification \"$message\" with title \"$title\"" >/dev/null 2>&1 || true
}

trap 'notify "Claude Desktop Backup Failed" "Script exited with an error — check ~/Library/Logs/claude-desktop-backup.log"' ERR

mkdir -p "$LATEST" "$SNAPSHOTS" "$(dirname "$LOG")"

rsync -a --delete --prune-empty-dirs \
  --include="claude_desktop_config.json" \
  --include="config.json" \
  --include="buddy-tokens.json" \
  --include="window-state.json" \
  --include="git-worktrees.json" \
  --include="plan-usage-history.json" \
  --include="cowork-enabled-cli-ops.json" \
  --include="claude-code-sessions/***" \
  --include="local-agent-mode-sessions/***" \
  --exclude="*/skills-plugin/" \
  --include="*/" \
  --exclude="*" \
  "$SRC/" "$LATEST/" >> "$LOG" 2>&1

# Dated snapshot of today's backup (hardlinked, so it costs no extra space
# unless a file actually changed).
rm -rf "$TODAY"
cp -al "$LATEST" "$TODAY" 2>>"$LOG" || cp -a "$LATEST" "$TODAY" >> "$LOG" 2>&1

# Prune snapshots beyond the most recent $KEEP. On cloud-synced folders,
# rm -rf can race with the sync daemon holding a file handle and leave an
# empty directory behind, so retry once and verify before declaring success.
find "$SNAPSHOTS" -mindepth 1 -maxdepth 1 -type d | sort -r | tail -n +$((KEEP + 1)) | while read -r old; do
  rm -rf "$old"
  if [ -d "$old" ]; then
    sleep 2
    rm -rf "$old"
  fi
  if [ -d "$old" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: failed to fully remove $old (will retry next run)" >> "$LOG"
    notify "Claude Desktop Backup Warning" "Could not fully remove old snapshot $(basename "$old") — check the log."
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
