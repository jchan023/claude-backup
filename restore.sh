#!/bin/bash
# Restores a claude-backup backup into ~/Library/Application Support/Claude
# and ~/.claude. See README.md's Restore section.
#
# Usage:
#   ./restore.sh              # restore from latest/
#   ./restore.sh --list       # list available dated snapshots
#   ./restore.sh 2026-08-09   # restore from snapshots/2026-08-09/
#   ./restore.sh -y           # skip the confirmation prompt (for scripting)
set -euo pipefail

ROOT="${CLAUDE_BACKUP_DEST:-$HOME/Backups/ClaudeDesktop}"
DESKTOP_DEST="$HOME/Library/Application Support/Claude"
CLI_DEST="$HOME/.claude"

ASSUME_YES=0
FROM="latest"
for arg in "$@"; do
  case "$arg" in
    -y|--yes) ASSUME_YES=1 ;;
    --list)
      echo "Available snapshots in $ROOT/snapshots:"
      find "$ROOT/snapshots" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r | xargs -n1 basename
      exit 0
      ;;
    *) FROM="$arg" ;;
  esac
done

if [ "$FROM" = "latest" ]; then
  SRC="$ROOT/latest"
else
  SRC="$ROOT/snapshots/$FROM"
fi

DESKTOP_SRC="$SRC/desktop"
CLI_SRC="$SRC/cli"

if [ ! -d "$DESKTOP_SRC" ] && [ ! -d "$CLI_SRC" ]; then
  echo "No backup found at $SRC" >&2
  echo "Run './restore.sh --list' to see available dated snapshots." >&2
  exit 1
fi

echo "Restoring from: $SRC"
[ -d "$DESKTOP_SRC" ] && echo "  Desktop -> $DESKTOP_DEST"
[ -d "$CLI_SRC" ] && echo "  CLI     -> $CLI_DEST"
echo
echo "This overwrites files already at those locations. Quit Claude Desktop"
echo "and the Claude Code CLI before continuing."

if [ "$ASSUME_YES" != "1" ]; then
  if [ ! -t 0 ]; then
    echo "Not running interactively — pass -y/--yes to confirm without a prompt." >&2
    exit 1
  fi
  read -rp "Continue? [y/N] " reply
  case "$reply" in
    [yY]|[yY][eE][sS]) ;;
    *) echo "Aborted."; exit 1 ;;
  esac
fi

if [ -d "$DESKTOP_SRC" ]; then
  mkdir -p "$DESKTOP_DEST"
  rsync -a "$DESKTOP_SRC/" "$DESKTOP_DEST/"
  echo "Restored Claude Desktop state."
fi

if [ -d "$CLI_SRC" ]; then
  mkdir -p "$CLI_DEST"
  rsync -a "$CLI_SRC/" "$CLI_DEST/"
  echo "Restored Claude Code CLI state."
fi

echo "Done. Relaunch Claude Desktop / the CLI."
