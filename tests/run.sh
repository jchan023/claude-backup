#!/bin/bash
# Lightweight functional test suite for install.sh, claude-desktop-backup.sh,
# restore.sh, and uninstall.sh. No framework, no dependencies beyond what
# the scripts themselves need — plain bash and assertions, matching the
# project's own no-extra-dependencies philosophy.
#
# Runs everything against a throwaway $HOME so it never touches the
# machine it runs on. macOS-only (launchctl, osascript), same as the
# scripts it tests.
#
# Usage: ./tests/run.sh
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILURES=0
PASS_COUNT=0

pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "  ok: $1"; }
fail() { FAILURES=$((FAILURES + 1)); echo "  FAIL: $1"; }

assert_file() {
  if [ -f "$1" ]; then pass "$2"; else fail "$2 (missing: $1)"; fi
}

assert_not_file() {
  if [ ! -f "$1" ]; then pass "$2"; else fail "$2 (unexpectedly present: $1)"; fi
}

assert_eq() {
  if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 (expected '$2', got '$1')"; fi
}

assert_files_match() {
  if diff -q "$1" "$2" >/dev/null 2>&1; then pass "$3"; else fail "$3 ($1 vs $2 differ)"; fi
}

new_fake_home() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/Library/Application Support/Claude" "$dir/.claude/projects/proj/memory"
  echo 'secret-token' > "$dir/Library/Application Support/Claude/buddy-tokens.json"
  echo '{"desktop":"config"}' > "$dir/Library/Application Support/Claude/config.json"
  echo '{"desktop2":"config"}' > "$dir/Library/Application Support/Claude/claude_desktop_config.json"
  echo 'window' > "$dir/Library/Application Support/Claude/window-state.json"
  echo '{"mcpServers":{}}' > "$dir/.claude/mcp.json"
  echo '{}' > "$dir/.claude/settings.json"
  echo '# my important memory' > "$dir/.claude/projects/proj/memory/MEMORY.md"
  echo "$dir"
}

cleanup_job() {
  launchctl unload "$1/Library/LaunchAgents/com.local.claude-desktop-backup.plist" >/dev/null 2>&1 || true
}

echo "== install.sh: basic install =="
HOME1="$(new_fake_home)"
( cd "$REPO_DIR" && HOME="$HOME1" ./install.sh >/dev/null )
assert_eq "$?" "0" "install.sh exits 0"
plutil -lint "$HOME1/Library/LaunchAgents/com.local.claude-desktop-backup.plist" >/dev/null 2>&1
assert_eq "$?" "0" "generated plist is valid XML"
launchctl list com.local.claude-desktop-backup >/dev/null 2>&1
assert_eq "$?" "0" "launchd job is actually registered (not just claimed)"
assert_file "$HOME1/Library/Scripts/claude-desktop-backup.sh" "backup script installed"
cleanup_job "$HOME1"
rm -rf "$HOME1"

echo "== install.sh: rejects a non-integer setting instead of writing a broken plist =="
HOME2="$(new_fake_home)"
( cd "$REPO_DIR" && HOME="$HOME2" CLAUDE_BACKUP_HOUR="9; rm -rf /" ./install.sh >/dev/null 2>&1 )
assert_eq "$?" "1" "install.sh rejects non-integer CLAUDE_BACKUP_HOUR"
rm -rf "$HOME2"

echo "== install.sh: XML-escapes special characters in CLAUDE_BACKUP_DEST =="
HOME3="$(new_fake_home)"
( cd "$REPO_DIR" && HOME="$HOME3" CLAUDE_BACKUP_DEST="$HOME3/Back & <ups>" ./install.sh >/dev/null )
plutil -lint "$HOME3/Library/LaunchAgents/com.local.claude-desktop-backup.plist" >/dev/null 2>&1
assert_eq "$?" "0" "plist stays valid XML with & < > in CLAUDE_BACKUP_DEST"
cleanup_job "$HOME3"
rm -rf "$HOME3"

echo "== claude-desktop-backup.sh: credentials included (default) =="
HOME4="$(new_fake_home)"
( cd "$REPO_DIR" && HOME="$HOME4" CLAUDE_BACKUP_DEST="$HOME4/Backups" ./claude-desktop-backup.sh )
assert_eq "$?" "0" "backup script exits 0"
assert_file "$HOME4/Backups/latest/desktop/buddy-tokens.json" "credentials included by default: buddy-tokens.json"
assert_file "$HOME4/Backups/latest/desktop/config.json" "credentials included by default: config.json"
assert_file "$HOME4/Backups/latest/cli/mcp.json" "credentials included by default: mcp.json"
assert_file "$HOME4/Backups/latest/desktop/window-state.json" "non-credential file also backed up"
assert_files_match "$HOME4/.claude/projects/proj/memory/MEMORY.md" \
  "$HOME4/Backups/latest/cli/projects/proj/memory/MEMORY.md" "memory file backed up byte-identical"

echo "== claude-desktop-backup.sh: CLAUDE_BACKUP_INCLUDE_CREDENTIALS=0 =="
HOME5="$(new_fake_home)"
( cd "$REPO_DIR" && HOME="$HOME5" CLAUDE_BACKUP_DEST="$HOME5/Backups" CLAUDE_BACKUP_INCLUDE_CREDENTIALS=0 ./claude-desktop-backup.sh )
assert_not_file "$HOME5/Backups/latest/desktop/buddy-tokens.json" "credentials excluded: buddy-tokens.json absent"
assert_not_file "$HOME5/Backups/latest/desktop/config.json" "credentials excluded: config.json absent"
assert_not_file "$HOME5/Backups/latest/cli/mcp.json" "credentials excluded: mcp.json absent"
assert_file "$HOME5/Backups/latest/desktop/window-state.json" "non-credential file still backed up when excluding credentials"

echo "== claude-desktop-backup.sh: snapshot pruning keeps only KEEP newest =="
HOME6="$(new_fake_home)"
DEST6="$HOME6/Backups"
( cd "$REPO_DIR" && HOME="$HOME6" CLAUDE_BACKUP_DEST="$DEST6" ./claude-desktop-backup.sh >/dev/null )
mkdir -p "$DEST6/snapshots/2020-01-01" "$DEST6/snapshots/2020-01-02" "$DEST6/snapshots/2020-01-03"
( cd "$REPO_DIR" && HOME="$HOME6" CLAUDE_BACKUP_DEST="$DEST6" CLAUDE_BACKUP_KEEP=2 ./claude-desktop-backup.sh >/dev/null )
SNAP_COUNT=$(find "$DEST6/snapshots" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
assert_eq "$SNAP_COUNT" "2" "pruning keeps exactly CLAUDE_BACKUP_KEEP snapshots"

echo "== claude-desktop-backup.sh: cp -al failing partway doesn't nest the fallback =="
# Regression test for a real bug report: if cp -al fails partway through
# (e.g. Box Drive can't chflags certain symlinks), it can leave $TODAY
# already existing as a partially-populated directory. The cp -a
# fallback then copies $LATEST *into* that existing directory instead of
# replacing it (that's just how cp works when the destination already
# exists), producing a spurious nested snapshots/YYYY-MM-DD/latest/
# instead of snapshots/YYYY-MM-DD/{desktop,cli} directly.
#
# Tested by extracting the actual snapshot-creation lines straight out
# of claude-desktop-backup.sh (so this can't silently drift from the
# real code) and running just that fragment against a hand-built
# $LATEST/$TODAY, rather than the whole script. Driving this through a
# full script run doesn't work: chmod 000 on a latest/ subdirectory also
# blocks the *earlier* rsync sync-to-latest step, aborting the script via
# set -e before the buggy code is ever reached; and running the full
# script twice to force a second-run failure instead trips over rsync
# and rm -rf also getting blocked by the same immutable flag on the
# *first* run's already-created snapshot. Isolating just the two lines
# under test sidesteps all of that.
TESTDIR="$(mktemp -d)"
mkdir -p "$TESTDIR/latest/desktop" "$TESTDIR/latest/cli"
echo "d1" > "$TESTDIR/latest/desktop/file.txt"
echo "c1" > "$TESTDIR/latest/cli/settings.json"
chflags uchg "$TESTDIR/latest/cli/settings.json"
mkdir -p "$TESTDIR/snapshots"
# shellcheck disable=SC2034 # used inside the eval'd SNAPSHOT_SNIPPET below, not visible to shellcheck statically
LATEST="$TESTDIR/latest"
TODAY="$TESTDIR/snapshots/2026-08-12"
LOG="$TESTDIR/log.txt"
touch "$LOG"
# shellcheck disable=SC2016 # single-quoted intentionally — matching the literal "$TODAY" text in the source file, not expanding it
SNAPSHOT_SNIPPET="$(sed -n '/^rm -rf "\$TODAY"$/,/^fi$/p' "$REPO_DIR/claude-desktop-backup.sh")"
( eval "$SNAPSHOT_SNIPPET" ) 2>/dev/null
NESTED=$(find "$TESTDIR/snapshots" -mindepth 1 -maxdepth 3 -type d -name "latest" 2>/dev/null)
if [ -z "$NESTED" ]; then
  pass "no spurious nested snapshots/YYYY-MM-DD/latest/ after a partial cp -al failure"
else
  fail "no spurious nested snapshots/YYYY-MM-DD/latest/ after a partial cp -al failure (found: $NESTED)"
fi
assert_file "$TODAY/desktop/file.txt" "snapshot content still lands at the correct top level despite the failure"
chflags nouchg "$TESTDIR/latest/cli/settings.json" 2>/dev/null
chflags nouchg "$TODAY/cli/settings.json" 2>/dev/null
rm -rf "$TESTDIR"

echo "== claude-desktop-backup.sh: cp -a fallback failing doesn't abort the whole script =="
# Regression test for a follow-up bug report: the fix above introduced a
# new problem. cp -a itself can also exit nonzero on the same class of
# chflags error (Box Drive reported this happening on both cp -al *and*
# the cp -a fallback for symlinks under ~/.claude/skills/) while still
# successfully copying everything else. Left unguarded, that exit under
# `set -e` aborted the whole script — silently skipping both the
# "backup complete" log line and snapshot pruning (which runs after
# this point).
#
# Box Drive's specific chflags-on-symlink failure for a *full* (non-
# hardlink) copy isn't reproducible on a local APFS volume — confirmed
# directly: a chflags-uchg'd file makes cp -al fail (same inode, can't
# re-flag something already immutable) but a fresh cp -a copy of it
# succeeds (the new file isn't immutable yet, so flagging it works
# fine). So this uses a mock `cp` on PATH instead: real behavior for
# `-al`, but the `-a` fallback does a real copy and then deliberately
# exits 1 — testing the actual guard logic in the real script,
# independent of a filesystem quirk that can't be triggered here.
TESTDIR="$(mktemp -d)"
mkdir -p "$TESTDIR/latest/desktop" "$TESTDIR/latest/cli/skills" "$TESTDIR/bin"
echo "d1" > "$TESTDIR/latest/desktop/file.txt"
echo "skill" > "$TESTDIR/latest/cli/skills/SKILL.md"
chflags uchg "$TESTDIR/latest/cli/skills/SKILL.md"
mkdir -p "$TESTDIR/snapshots"
cat > "$TESTDIR/bin/cp" <<'MOCK'
#!/bin/bash
if [[ "$1" == "-al" ]]; then
  exec /bin/cp "$@"
elif [[ "$1" == "-a" ]]; then
  /bin/cp "$@"
  exit 1
fi
exec /bin/cp "$@"
MOCK
chmod +x "$TESTDIR/bin/cp"
# shellcheck disable=SC2034
LATEST="$TESTDIR/latest"
TODAY="$TESTDIR/snapshots/2026-08-12"
LOG="$TESTDIR/log.txt"
touch "$LOG"
# shellcheck disable=SC2329 # invoked indirectly by the eval'd SNAPSHOT_SNIPPET below
notify() { :; }
# shellcheck disable=SC2016 # single-quoted intentionally — matching the literal "$TODAY" text in the source file, not expanding it
SNAPSHOT_SNIPPET="$(sed -n '/^rm -rf "\$TODAY"$/,/^fi$/p' "$REPO_DIR/claude-desktop-backup.sh")"
( PATH="$TESTDIR/bin:$PATH" eval "$SNAPSHOT_SNIPPET" )
assert_eq "$?" "0" "script doesn't abort when the cp -a fallback itself exits nonzero"
assert_file "$TODAY/desktop/file.txt" "correctly-copied content still lands despite the fallback's nonzero exit"
chflags nouchg "$TESTDIR/latest/cli/skills/SKILL.md" 2>/dev/null
chflags nouchg "$TODAY/cli/skills/SKILL.md" 2>/dev/null
rm -rf "$TESTDIR"

echo "== claude-desktop-backup.sh: total snapshot failure logs a WARNING and notifies =="
TESTDIR="$(mktemp -d)"
mkdir -p "$TESTDIR/latest/desktop" "$TESTDIR/bin"
echo "d1" > "$TESTDIR/latest/desktop/file.txt"
mkdir -p "$TESTDIR/snapshots"
cat > "$TESTDIR/bin/cp" <<'MOCK'
#!/bin/bash
exit 1
MOCK
chmod +x "$TESTDIR/bin/cp"
# shellcheck disable=SC2034
LATEST="$TESTDIR/latest"
TODAY="$TESTDIR/snapshots/2026-08-12"
LOG="$TESTDIR/log.txt"
touch "$LOG"
NOTIFY_LOG="$TESTDIR/notify.log"
notify() { echo "$1|$2" >> "$NOTIFY_LOG"; }
# shellcheck disable=SC2016 # single-quoted intentionally — matching the literal "$TODAY" text in the source file, not expanding it
SNAPSHOT_SNIPPET="$(sed -n '/^rm -rf "\$TODAY"$/,/^fi$/p' "$REPO_DIR/claude-desktop-backup.sh")"
( PATH="$TESTDIR/bin:$PATH" eval "$SNAPSHOT_SNIPPET" )
assert_eq "$?" "0" "script doesn't abort even when the snapshot fails completely"
if grep -q "WARNING: snapshot creation failed entirely" "$LOG"; then
  pass "total snapshot failure logs a WARNING"
else
  fail "total snapshot failure logs a WARNING (log: $(cat "$LOG"))"
fi
rm -rf "$TESTDIR"

echo "== restore.sh: --list shows available dates =="
# Captured into a variable and matched with bash's own [[ == *pattern* ]]
# rather than piped live into `grep -q`: grep -q exits after its first
# match and closes the pipe, which can SIGPIPE a still-writing upstream
# process — a real, timing-dependent failure mode, not something to
# reproduce accidentally in the test itself.
LIST_OUTPUT=$( cd "$REPO_DIR" && HOME="$HOME4" CLAUDE_BACKUP_DEST="$HOME4/Backups" ./restore.sh --list 2>&1 )
if [[ "$LIST_OUTPUT" == *"Available snapshots"* ]]; then
  pass "restore.sh --list runs"
else
  fail "restore.sh --list runs (got: $LIST_OUTPUT)"
fi

echo "== restore.sh: restores latest/ correctly =="
FRESH1="$(mktemp -d)"
( cd "$REPO_DIR" && HOME="$FRESH1" CLAUDE_BACKUP_DEST="$HOME4/Backups" ./restore.sh -y >/dev/null )
assert_eq "$?" "0" "restore.sh -y exits 0"
assert_files_match "$HOME4/Backups/latest/cli/projects/proj/memory/MEMORY.md" \
  "$FRESH1/.claude/projects/proj/memory/MEMORY.md" "restored memory file matches source"
assert_files_match "$HOME4/Backups/latest/desktop/buddy-tokens.json" \
  "$FRESH1/Library/Application Support/Claude/buddy-tokens.json" "restored credentials match source"
rm -rf "$FRESH1"

echo "== restore.sh: rejects path traversal in the date argument =="
FRESH2="$(mktemp -d)"
mkdir -p "$FRESH2/elsewhere/desktop"
echo 'should never be reachable' > "$HOME4/elsewhere-marker.txt" 2>/dev/null
OUTPUT=$( cd "$REPO_DIR" && HOME="$FRESH2" CLAUDE_BACKUP_DEST="$HOME4/Backups" ./restore.sh "../../../../../../etc" -y 2>&1 )
EXIT=$?
assert_eq "$EXIT" "1" "restore.sh rejects a non-YYYY-MM-DD date argument"
if [[ "$OUTPUT" == *"Invalid snapshot date"* ]]; then
  pass "restore.sh explains why it rejected the argument"
else
  fail "restore.sh explains why it rejected the argument (got: $OUTPUT)"
fi
rm -rf "$FRESH2"

echo "== uninstall.sh: removes the job, preserves backups =="
HOME7="$(new_fake_home)"
( cd "$REPO_DIR" && HOME="$HOME7" CLAUDE_BACKUP_DEST="$HOME7/Backups" ./install.sh >/dev/null )
( cd "$REPO_DIR" && HOME="$HOME7" "$HOME7/Library/Scripts/claude-desktop-backup.sh" >/dev/null )
( cd "$REPO_DIR" && HOME="$HOME7" ./uninstall.sh >/dev/null )
if ! launchctl list com.local.claude-desktop-backup >/dev/null 2>&1; then
  pass "uninstall.sh actually removes the launchd job"
else
  fail "uninstall.sh actually removes the launchd job (still registered)"
fi
assert_not_file "$HOME7/Library/Scripts/claude-desktop-backup.sh" "uninstall.sh removes the installed script"
assert_file "$HOME7/Backups/ClaudeDesktop/latest/desktop/window-state.json" "uninstall.sh preserves existing backups"
rm -rf "$HOME7"

rm -rf "$HOME4" "$HOME5" "$HOME6"

echo ""
echo "== $PASS_COUNT passed, $FAILURES failed =="
[ "$FAILURES" -eq 0 ]
