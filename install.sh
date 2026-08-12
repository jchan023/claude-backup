#!/bin/bash
# Installs claude-desktop-backup.sh and a launchd job that runs it daily.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_SCRIPT="$HOME/Library/Scripts/claude-desktop-backup.sh"
# Overridable so tests/run.sh can use a unique label — launchctl
# load/unload resolve jobs by Label within the whole gui/<uid> launchd
# domain, which isn't scoped by $HOME at all. A test install using the
# same default label as a real production install would silently take
# the real job down when the test uninstalls, even though every file
# path involved is otherwise correctly confined to a fake $HOME.
PLIST_LABEL="${CLAUDE_BACKUP_PLIST_LABEL:-com.local.claude-desktop-backup}"
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
INCLUDE_CREDENTIALS="${CLAUDE_BACKUP_INCLUDE_CREDENTIALS:-1}"

xml_escape() {
  # & must come first so the escapes for the other characters aren't
  # themselves re-escaped.
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g' -e "s/'/\\&apos;/g"
}

for n in "$HOUR" "$MINUTE" "$KEEP" "$MAX_LOG_LINES" "$NOTIFY" "$INCLUDE_CREDENTIALS"; do
  case "$n" in
    ''|*[!0-9]*)
      echo "CLAUDE_BACKUP_HOUR/MINUTE/KEEP/LOG_MAX_LINES/NOTIFY/INCLUDE_CREDENTIALS must all be plain integers, got: '$n'" >&2
      exit 1
      ;;
  esac
done

DEST_ESC="$(xml_escape "$DEST")"
DEST_SCRIPT_ESC="$(xml_escape "$DEST_SCRIPT")"
LOG_ESC="$(xml_escape "$LOG")"

# Clean up the wrapper .app from 1.5.0/1.5.1, if present — that approach
# didn't actually scope Full Disk Access (see CHANGELOG.md) and was
# reverted; ProgramArguments below points at /bin/bash directly again.
rm -rf "$HOME/Library/Application Support/ClaudeBackup.app"

mkdir -p "$HOME/Library/Scripts" "$HOME/Library/LaunchAgents" "$(dirname "$LOG")"
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
        <string>$DEST_SCRIPT_ESC</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>CLAUDE_BACKUP_DEST</key>
        <string>$DEST_ESC</string>
        <key>CLAUDE_BACKUP_KEEP</key>
        <string>$KEEP</string>
        <key>CLAUDE_BACKUP_LOG_MAX_LINES</key>
        <string>$MAX_LOG_LINES</string>
        <key>CLAUDE_BACKUP_NOTIFY</key>
        <string>$NOTIFY</string>
        <key>CLAUDE_BACKUP_INCLUDE_CREDENTIALS</key>
        <string>$INCLUDE_CREDENTIALS</string>
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
    <string>$LOG_ESC</string>
    <key>StandardErrorPath</key>
    <string>$LOG_ESC</string>
</dict>
</plist>
PLIST

launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"

# `launchctl load` can print "Load failed" and still exit 0 (a known
# quirk), so confirm the job actually registered instead of trusting its
# own exit status — otherwise this would print success on a job that
# silently isn't scheduled at all.
if ! launchctl list "$PLIST_LABEL" >/dev/null 2>&1; then
  echo "launchctl reported the job as loaded, but it isn't registered — check for XML/plist errors:" >&2
  plutil -lint "$PLIST_PATH" >&2 || true
  exit 1
fi

echo "Installed $DEST_SCRIPT"
echo "Loaded launchd job '$PLIST_LABEL' (runs daily at $HOUR:$(printf '%02d' "$MINUTE"))"
echo "Backups go to: $DEST (keeping $KEEP snapshots)"
if [ "$INCLUDE_CREDENTIALS" = "1" ]; then
  echo "Credentials: included (buddy-tokens.json, config.json, mcp.json, etc.)"
else
  echo "Credentials: excluded"
fi
echo "Logs: $LOG"
