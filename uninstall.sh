#!/bin/bash
# Removes the launchd job, installed script, and wrapper app. Does not
# touch existing backups.
set -euo pipefail

PLIST_LABEL="com.local.claude-desktop-backup"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"
DEST_SCRIPT="$HOME/Library/Scripts/claude-desktop-backup.sh"
APP_DIR="$HOME/Library/Application Support/ClaudeBackup.app"

launchctl unload "$PLIST_PATH" 2>/dev/null || true
rm -f "$PLIST_PATH" "$DEST_SCRIPT"
rm -rf "$APP_DIR"

echo "Removed launchd job, script, and wrapper app. Backup files were left in place."
