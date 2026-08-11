#!/bin/bash
# Installs claude-desktop-backup.sh, wraps it in a minimal .app bundle, and
# installs a launchd job that runs the wrapper daily.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_SCRIPT="$HOME/Library/Scripts/claude-desktop-backup.sh"
APP_DIR="$HOME/Library/Application Support/ClaudeBackup.app"
APP_EXECUTABLE="$APP_DIR/Contents/MacOS/claude-desktop-backup"
BUNDLE_ID="com.local.claude-desktop-backup"
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

APP_EXECUTABLE_ESC="$(xml_escape "$APP_EXECUTABLE")"
DEST_ESC="$(xml_escape "$DEST")"
LOG_ESC="$(xml_escape "$LOG")"

mkdir -p "$HOME/Library/Scripts" "$HOME/Library/LaunchAgents" "$(dirname "$LOG")"
cp "$SCRIPT_DIR/claude-desktop-backup.sh" "$DEST_SCRIPT"
chmod +x "$DEST_SCRIPT"

# Wrap the script in a minimal .app bundle instead of pointing the launchd
# job at the shared system /bin/bash directly. A bundle's "executable"
# only needs to be a valid ELF/Mach-O binary or, as here, a script with a
# shebang — no compiler needed (the same trick tools like Platypus use).
# The point: Full Disk Access can then be granted to this one app
# specifically, instead of to /bin/bash system-wide, which every other
# shell script on the machine would otherwise also inherit. See
# README.md's Troubleshooting section.
mkdir -p "$APP_DIR/Contents/MacOS"
cat > "$APP_DIR/Contents/Info.plist" <<INFOPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>ClaudeBackup</string>
    <key>CFBundleExecutable</key>
    <string>claude-desktop-backup</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSBackgroundOnly</key>
    <true/>
</dict>
</plist>
INFOPLIST
cp "$SCRIPT_DIR/claude-desktop-backup.sh" "$APP_EXECUTABLE"
chmod +x "$APP_EXECUTABLE"

# Ad-hoc sign (no paid Developer ID needed — this never leaves the
# machine it's built on) so the bundle has a stable identity for TCC and
# so Gatekeeper doesn't need to make a first-launch trust decision.
if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "$APP_DIR" 2>/dev/null || echo "Warning: codesign failed; continuing with an unsigned bundle." >&2
else
  echo "Warning: codesign not found; continuing with an unsigned bundle." >&2
fi

# Register with Launch Services so System Settings' Full Disk Access
# file picker recognizes it properly (name/icon) rather than as a bare
# unknown bundle.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
  "$LSREGISTER" -f "$APP_DIR" >/dev/null 2>&1 || true
fi

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$APP_EXECUTABLE_ESC</string>
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
echo "Wrapper app: $APP_DIR"
echo "Loaded launchd job '$PLIST_LABEL' (runs daily at $HOUR:$(printf '%02d' "$MINUTE"))"
echo "Backups go to: $DEST (keeping $KEEP snapshots)"
if [ "$INCLUDE_CREDENTIALS" = "1" ]; then
  echo "Credentials: included (buddy-tokens.json, config.json, mcp.json, etc.)"
else
  echo "Credentials: excluded"
fi
echo "Logs: $LOG"
echo ""
echo "If your backup destination is under ~/Library/CloudStorage/ (Google"
echo "Drive, OneDrive, iCloud Drive, or similar), grant Full Disk Access to:"
echo "  $APP_DIR"
echo "System Settings -> Privacy & Security -> Full Disk Access -> + -> Cmd+Shift+G -> paste that path."