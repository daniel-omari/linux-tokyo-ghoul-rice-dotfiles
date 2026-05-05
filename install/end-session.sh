#!/usr/bin/env bash
# =============================================================================
# end-session.sh — sync chezmoi clone + working clone to GitHub
#
# Run at the end of a ricing session. Handles the dual-clone dance:
# 1. Pulls remote changes into both clones (so neither is behind).
# 2. Stages, commits, and pushes any local changes.
# 3. Re-syncs so both clones end up identical to GitHub.
#
# Usage: ./end-session.sh ["optional commit message"]
# =============================================================================

set -e  # exit immediately on any error

WORKING_REPO="$HOME/linux-tokyo-ghoul-rice-dotfiles"
CHEZMOI_REPO="$HOME/.local/share/chezmoi"

# Allow custom commit message; otherwise auto-generate one with timestamp.
MSG="${1:-Session sync: $(date '+%Y-%m-%d %H:%M')}"

# ---- Helper: sync one repo --------------------------------------------------
sync_repo() {
    local repo_path="$1"
    local repo_label="$2"

    echo ""
    echo "==> [$repo_label]  $repo_path"

    if [ ! -d "$repo_path/.git" ]; then
        echo "    SKIP: not a git repo"
        return
    fi

    cd "$repo_path"

    # Refuse to touch a repo mid-merge or mid-rebase
    if [ -d ".git/rebase-merge" ] || [ -d ".git/rebase-apply" ] || [ -f ".git/MERGE_HEAD" ]; then
        echo "    ERROR: repo is mid-rebase or mid-merge — fix manually first"
        return 1
    fi

    # Pull first so we never push into a stale ref
    echo "    Pulling..."
    git pull --rebase --autostash

    # Check for uncommitted changes
    if [ -z "$(git status --porcelain)" ]; then
        echo "    Nothing to commit."
    else
        echo "    Local changes detected:"
        git status --short | sed 's/^/      /'
        echo "    Committing..."
        git add -A
        git commit -m "$MSG"
        echo "    Pushing..."
        git push
    fi

    echo "    Done."
}

# ---- Run ---------------------------------------------------------------------
echo "=========================================="
echo "  End-of-session sync"
echo "  Commit message: $MSG"
echo "=========================================="

sync_repo "$CHEZMOI_REPO" "chezmoi clone"
sync_repo "$WORKING_REPO" "working clone"

# Final pass on chezmoi to pull anything the working clone just pushed
echo ""
echo "==> Final re-sync of chezmoi clone..."
cd "$CHEZMOI_REPO"
git pull --rebase --autostash

echo ""
echo "=========================================="
echo "  Session synced. Both clones aligned with GitHub."
echo "=========================================="
