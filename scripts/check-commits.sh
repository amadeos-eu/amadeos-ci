#!/usr/bin/env bash
# Checks that the commits of a pull request are Conventional Commits, so that the next version can be
# computed from them (next-version.sh). Merge commits are not checked.
#
# Usage: scripts/check-commits.sh <base> <head> [<pull request title>]
#
# The title is checked too when it is given: in a repository that squash-merges it becomes the commit.
set -euo pipefail

base=${1:?usage: check-commits.sh <base> <head> [title]}
head=${2:?usage: check-commits.sh <base> <head> [title]}
title=${3:-}
pattern='^(feat|fix|perf|refactor|docs|test|build|ci|chore|style|revert)(\([a-z0-9][a-z0-9./-]*\))?!?: [^ ]'

bad=0
while IFS=' ' read -r sha subject; do
    if ! grep -qE "$pattern" <<<"$subject"; then
        echo "::error::Commit ${sha:0:10} is no Conventional Commit: $subject"
        bad=1
    fi
done < <(git log --no-merges --format='%H %s' "$base..$head")
if [ -n "$title" ] && ! grep -qE "$pattern" <<<"$title"; then
    echo "::error::The pull request title is no Conventional Commit: $title"
    bad=1
fi

if [ "$bad" = 1 ]; then
    cat <<'HELP'
Write commit subjects as  type(scope): text  , for example
    feat(panel): battery cell in the status slot
    fix(wm): closing a dialog activates its owner
    docs(handbook): chapter 63 explains the battery cell
Types: feat (new feature, minor version), fix and perf (patch version), refactor, docs, test, build,
ci, chore, style, revert. A ! after the type or scope, or a "BREAKING CHANGE: ..." line in the body,
marks a breaking change (major version). Rename commits with git rebase -i and push with
--force-with-lease. See CONTRIBUTING.md, "Commits and versions".
HELP
    exit 1
fi
echo "All commits are Conventional Commits."
