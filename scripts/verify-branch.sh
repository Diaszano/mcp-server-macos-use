#!/bin/sh
# scripts/verify-branch.sh
# Verifies a branch name against Conventional Branch (https://conventional-branch.github.io/)
# Usage: ./scripts/verify-branch.sh [branch]   (defaults to the current branch)

BRANCH="${1:-$(git rev-parse --abbrev-ref HEAD)}"

case "$BRANCH" in
    # Default branch and bot-managed branches (release-please, Dependabot)
    main|HEAD|release-please--*|dependabot/*) exit 0 ;;
esac

TYPES="feat|fix|hotfix|release|chore|docs|refactor|test|ci|build|perf|style|revert"
# Optional Jira-style key (e.g. PROJ-123-) followed by a lowercase kebab-case description.
PATTERN="^($TYPES)/([A-Z][A-Z0-9]+-[0-9]+-)?[a-z0-9]+([.-][a-z0-9]+)*$"

if echo "$BRANCH" | grep -Eq "$PATTERN"; then
    exit 0
fi

cat >&2 <<MSG
================================================================================
❌ INVALID BRANCH NAME (Conventional Branch violation): "$BRANCH"
================================================================================
Expected: <type>/<description>  (lowercase, kebab-case)

Allowed types: ${TYPES}

Examples:
  feat/volume-search
  fix/socket-discovery
  fix/PROJ-123-order-total
  release/v1.2.0

Rename with: git branch -m <new-name>
================================================================================
MSG
exit 1
