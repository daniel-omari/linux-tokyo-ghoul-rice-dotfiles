#!/usr/bin/env bash
# =============================================================================
# end-session.sh — auto-sync local changes to a draft branch on GitHub
#
# Pushes uncommitted work in both clones (chezmoi + working) to the AUTO_BRANCH
# on origin. Never touches the main branch — that's reserved for intentional,
# human-reviewed merges.
#
# When promoting work from auto-sync to main:
#   cd ~/linux-tokyo-ghoul-rice-dotfiles
#   git checkout main
#   git merge auto-sync --squash
#   git commit -m "Meaningful description of session's work"
#   git push
#   git checkout auto-sync && git reset --hard main && git push --force-with-lease
#
# Usage: ./end-session.sh ["optional commit message"]
# =============================================================================

set -e

WORKING_REPO="$HOME/linux-tokyo-ghoul-rice-dotfiles"
CHEZMOI_REPO="$HOME/.local/share/chezmoi"
AUTO_BRANCH="auto-sync"

MSG="${1:-Auto-sync: $(date '+%Y-%m-%d %H:%M')}"

# ---- Helper: ensure AUTO_BRANCH exists on remote, create from main if not ----
ensure_remote_branch() {
    local repo_path="$1"
    cd "$repo_path"

    git fetch origin --quiet

    if git ls-remote --exit-code --heads origin "$AUTO_BRANCH" >/dev/null 2>&1; then
        return 0  # remote branch exists, nothing to do
    fi

    echo "    Remote branch '$AUTO_BRANCH' doesn't exist yet — creating from main..."
    # Create local branch tracking origin/main, then push it as auto-sync
    git checkout -B "$AUTO_BRANCH" origin/main
    git push -u origin "$AUTO_BRANCH"
}

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

    # Refuse to operate mid-merge or mid-rebase
    if [ -d ".git/rebase-merge" ] || [ -d ".git/rebase-apply" ] || [ -f ".git/MERGE_HEAD" ]; then
        echo "    ERROR: repo is mid-rebase or mid-merge — fix manually first"
        return 1
    fi

    # Make sure auto-sync exists on the remote
    ensure_remote_branch "$repo_path"

    # Remember which branch the user was on, so we can restore it after
    local original_branch
    original_branch=$(git rev-parse --abbrev-ref HEAD)

    # If there are uncommitted changes, stash them so we can switch branches
    local stashed=0
    if [ -n "$(git status --porcelain)" ]; then
        echo "    Stashing local changes to switch branches..."
        git stash push -u -m "endsession-tmp" >/dev/null
        stashed=1
    fi

    # Switch to auto-sync, pulling its current state from origin
    echo "    Switching to '$AUTO_BRANCH'..."
    git checkout "$AUTO_BRANCH" 2>/dev/null || git checkout -B "$AUTO_BRANCH" "origin/$AUTO_BRANCH"
    git pull --rebase --autostash origin "$AUTO_BRANCH"

    # Restore stashed changes onto auto-sync
    if [ "$stashed" = "1" ]; then
        echo "    Reapplying stashed changes onto '$AUTO_BRANCH'..."
        git stash pop
    fi

    # Commit + push if there's anything new
    if [ -z "$(git status --porcelain)" ]; then
        echo "    Nothing to commit."
    else
        echo "    Local changes:"
        git status --short | sed 's/^/      /'
        git add -A
        git commit -m "$MSG"
        echo "    Pushing to origin/$AUTO_BRANCH..."
        git push origin "$AUTO_BRANCH"
    fi

    # Switch back to original branch so the user's working state is preserved
    if [ "$original_branch" != "$AUTO_BRANCH" ]; then
        echo "    Switching back to '$original_branch'..."
        git checkout "$original_branch"
    fi

    echo "    Done."
}

# ---- Run ---------------------------------------------------------------------
echo "=========================================="
echo "  End-of-session auto-sync"
echo "  Target branch: $AUTO_BRANCH"
echo "  Commit message: $MSG"
echo "=========================================="

sync_repo "$CHEZMOI_REPO" "chezmoi clone"
sync_repo "$WORKING_REPO" "working clone"

echo ""
echo "=========================================="
echo "  Synced to origin/$AUTO_BRANCH."
echo "  Review on GitHub, then merge to main when ready:"
echo ""
echo "    cd $WORKING_REPO"
echo "    git checkout main"
echo "    git merge $AUTO_BRANCH --squash"
echo "    git commit -m \"<your message>\""
echo "    git push"
echo "=========================================="
