#!/bin/bash
# Installs claude-desktop-backup.sh, wraps it in a minimal .app bundle, and
# installs a launchd job that runs the wrapper daily.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_SCRIPT="$HOME/Library/Scripts/claude-desktop-backup.sh"
APP_DIR="$HOME/Library/Application Support/ClaudeBackup.app"
# osacompile always names its compiled binary "applet" — not
# configurable, and not worth renaming after the fact.
APP_EXECUTABLE="$APP_DIR/Contents/MacOS/applet"
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
# job at the shared system /bin/bash directly, so Full Disk Access can be
# granted to this one app specifically instead of to /bin/bash
# system-wide (which every other shell script on the machine would
# otherwise also inherit). See README.md's Troubleshooting section.
#
# This MUST be a real compiled binary, not a script with a #!/bin/bash
# shebang — confirmed the hard way: a shebang "executable" causes the
# kernel to exec /bin/bash as the actual running process, and TCC's
# Full Disk Access check is keyed to that process, not to the bundle
# nominally wrapping it. A shebang wrapper creates no TCC identity of
# its own at all and silently piggybacks on whatever grant /bin/bash
# already has — verified directly against the TCC database. osacompile
# (ships with macOS, no Xcode needed) produces an actual Mach-O binary
# that gets its own distinct, independently-evaluated TCC identity —
# also verified directly: an ungranted osacompile app gets a real
# (denied) entry in the TCC database, unlike the shebang version.
rm -rf "$APP_DIR"
APPLESCRIPT_SRC="$(mktemp)"
trap 'rm -f "$APPLESCRIPT_SRC"' EXIT
printf 'do shell script "%s"\n' "'${DEST_SCRIPT}'" > "$APPLESCRIPT_SRC"
osacompile -o "$APP_DIR" "$APPLESCRIPT_SRC"
rm -f "$APPLESCRIPT_SRC"
trap - EXIT

# osacompile doesn't set a CFBundleIdentifier by default — without one,
# TCC has no stable identity to remember a grant against between runs.
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$APP_DIR/Contents/Info.plist"
plutil -replace LSUIElement -bool true "$APP_DIR/Contents/Info.plist"

# Editing Info.plist after osacompile's own signing invalidates that
# signature, so re-sign. Ad hoc (no paid Developer ID needed — this
# never leaves the machine it's built on) just to give the bundle a
# stable identity and avoid a Gatekeeper first-launch decision.
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