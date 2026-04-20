#!/usr/bin/env bash
# setup-memory.sh — wire Claude Code's auto-memory to the repo's .claude/memory/
#
# Run this ONCE after cloning the repo on a new machine.
# Idempotent: safe to re-run.
#
# What it does:
#   Claude Code's auto-memory lives at  ~/.claude/projects/<project-id>/memory/
#   where <project-id> is the absolute project path with "/" replaced by "-".
#   That path is OS-local and not portable across machines / clones.
#
#   This script symlinks that location to <repo>/.claude/memory/, so the
#   memory files live in the repo (committable, portable) while Claude
#   still finds them at the path it expects.

set -euo pipefail

# Resolve repo root from this script's location (works regardless of cwd)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_MEMORY="$REPO_ROOT/.claude/memory"

if [ ! -d "$REPO_MEMORY" ]; then
    echo "✗ Expected $REPO_MEMORY to exist (with MEMORY.md)." >&2
    echo "  Are you running this from the HLD repo?" >&2
    exit 1
fi

# Derive Claude's project ID: absolute path with "/" → "-"
PROJECT_ID="${REPO_ROOT//\//-}"
CLAUDE_DIR="$HOME/.claude/projects/$PROJECT_ID"
CLAUDE_MEMORY="$CLAUDE_DIR/memory"

mkdir -p "$CLAUDE_DIR"

# If something already exists at the target, handle it safely
if [ -L "$CLAUDE_MEMORY" ]; then
    # Existing symlink — check where it points
    EXISTING_TARGET="$(readlink "$CLAUDE_MEMORY")"
    if [ "$EXISTING_TARGET" = "$REPO_MEMORY" ]; then
        echo "✓ Already linked: $CLAUDE_MEMORY -> $REPO_MEMORY"
        exit 0
    fi
    echo "  Replacing existing symlink (was → $EXISTING_TARGET)"
    rm "$CLAUDE_MEMORY"
elif [ -e "$CLAUDE_MEMORY" ]; then
    # Real directory — back it up so we don't lose anything
    BACKUP="$CLAUDE_MEMORY.backup.$(date +%Y%m%d-%H%M%S)"
    echo "  Found existing memory directory at $CLAUDE_MEMORY"
    echo "  Backing up to $BACKUP"
    mv "$CLAUDE_MEMORY" "$BACKUP"
fi

ln -s "$REPO_MEMORY" "$CLAUDE_MEMORY"
echo "✓ Linked $CLAUDE_MEMORY -> $REPO_MEMORY"
echo ""
echo "Claude's auto-memory will now read/write files inside the repo."
echo "Commit changes under .claude/memory/ to share them across machines."
