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
# Defaulted here (not just in the script) because launchd does not inherit
# your shell's environment — anything the script should see at run time
# must be baked into the plist's EnvironmentVariables block below.
DEST="${CLAUDE_BACKUP_DEST:-$HOME/Backups/ClaudeDesktop}"
KEEP="${CLAUDE_BACKUP_KEEP:-3}"
MAX_LOG_LINES="${CLAUDE_BACKUP_LOG_MAX_LINES:-2000}"
NOTIFY="${CLAUDE_BACKUP_NOTIFY:-1}"

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
    <key>EnvironmentVariables</key>
    <dict>
        <key>CLAUDE_BACKUP_DEST</key>
        <string>$DEST</string>
        <key>CLAUDE_BACKUP_KEEP</key>
        <string>$KEEP</string>
        <key>CLAUDE_BACKUP_LOG_MAX_LINES</key>
        <string>$MAX_LOG_LINES</string>
        <key>CLAUDE_BACKUP_NOTIFY</key>
        <string>$NOTIFY</string>
    </dict>
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
echo "Backups go to: $DEST (keeping $KEEP snapshots)"
echo "Logs: $LOG"
