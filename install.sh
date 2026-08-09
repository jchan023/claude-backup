#!/bin/bash
# Installs claude-desktop-backup.sh and a launchd job that runs it daily.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_SCRIPT="$HOME/Library/Scripts/claude-desktop-backup.sh"
PLIST_LABEL="com.local.claude-desktop-backup"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"
LOG="$HOME/Library/Logs/claude-desktop-backup.log"
HOUR="${CLAUDE_BACKUP_HOUR:-9}"
MINUTE="${CLAUDE_BACKUP_MINUTE:-0}"

mkdir -p "$HOME/Library/Scripts" "$HOME/Library/LaunchAgents"
cp "$SCRIPT_DIR/claude-desktop-backup.sh" "$DEST_SCRIPT"
chmod +x "$DEST_SCRIPT"

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$DEST_SCRIPT</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>$HOUR</integer>
        <key>Minute</key>
        <integer>$MINUTE</integer>
    </dict>
    <key>RunAtLoad</key>
    <false/>
    <key>StandardOutPath</key>
    <string>$LOG</string>
    <key>StandardErrorPath</key>
    <string>$LOG</string>
</dict>
</plist>
PLIST

launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"

echo "Installed $DEST_SCRIPT"
echo "Loaded launchd job '$PLIST_LABEL' (runs daily at $HOUR:$(printf '%02d' "$MINUTE"))"
echo "Backups go to: \${CLAUDE_BACKUP_DEST:-\$HOME/Dropbox/Backups/ClaudeDesktop}"
echo "Logs: $LOG"
