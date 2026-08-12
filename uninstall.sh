#!/bin/bash
# Removes the launchd job and installed script. Does not touch existing backups.
set -euo pipefail

# Must match install.sh's default/override so uninstall targets the
# same job it installed — see install.sh for why this is overridable.
PLIST_LABEL="${CLAUDE_BACKUP_PLIST_LABEL:-com.local.claude-desktop-backup}"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"
DEST_SCRIPT="$HOME/Library/Scripts/claude-desktop-backup.sh"

launchctl unload "$PLIST_PATH" 2>/dev/null || true
rm -f "$PLIST_PATH" "$DEST_SCRIPT"

echo "Removed launchd job and script. Backup files were left in place."
