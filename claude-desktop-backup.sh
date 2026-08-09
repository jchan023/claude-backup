#!/bin/bash
# Backs up Claude Desktop's config, auth tokens, and session history to
# Dropbox (or any other target directory), keeping a small number of
# rotating dated snapshots. See README.md for setup via install.sh.
set -euo pipefail

SRC="$HOME/Library/Application Support/Claude"
ROOT="${CLAUDE_BACKUP_DEST:-$HOME/Dropbox/Backups/ClaudeDesktop}"
LATEST="$ROOT/latest"
SNAPSHOTS="$ROOT/snapshots"
TODAY="$SNAPSHOTS/$(date '+%Y-%m-%d')"
LOG="$HOME/Library/Logs/claude-desktop-backup.log"
KEEP="${CLAUDE_BACKUP_KEEP:-3}"

mkdir -p "$LATEST" "$SNAPSHOTS"

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

# Prune snapshots beyond the most recent $KEEP.
ls -1d "$SNAPSHOTS"/*/ 2>/dev/null | sort -r | tail -n +$((KEEP + 1)) | while read -r old; do
  rm -rf "$old"
  echo "$(date '+%Y-%m-%d %H:%M:%S') pruned $old" >> "$LOG"
done

echo "$(date '+%Y-%m-%d %H:%M:%S') backup complete" >> "$LOG"
