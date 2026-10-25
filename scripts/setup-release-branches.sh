#!/usr/bin/env bash
# One-time setup of the release branches in the amadeOS repositories, with the GitHub CLI (gh auth login):
# lets pull requests be merged with a merge commit only (no squash, no rebase), creates develop and
# release at the current main, makes develop the default branch, and protects main and release with a
# ruleset that allows fast-forwards only (no force push, no deletion).
#
# Usage: scripts/setup-release-branches.sh [repository ...]
#
#   Without repositories: all of amadeos/repositories.list, then amadeos. The merge settings are applied
#   every time; the branches of repositories that have develop already are left alone, so the script can
#   run again. Merge open pull requests first, or change their base to
#   develop afterwards.
set -euo pipefail

if [ $# -gt 0 ]; then
    repos=("$@")
else
    mapfile -t repos < <(gh api repos/datazuul/amadeos/contents/repositories.list -H 'Accept: application/vnd.github.raw' \
                             | sed -e 's/#.*//' -e '/^[[:space:]]*$/d' -e 's/[[:space:]]//g')
    repos+=(amadeos)
fi

for repo in "${repos[@]}"; do
    echo "== $repo"
    # Merge commits keep the commits of a pull request, which the version count and the handbook pins need.
    gh api -X PATCH "repos/datazuul/$repo" -F allow_merge_commit=true -F allow_squash_merge=false \
        -F allow_rebase_merge=false >/dev/null
    echo "  pull requests: merge commits only"
    if gh api "repos/datazuul/$repo/branches/develop" >/dev/null 2>&1; then
        echo "  has develop already; branches left as they are"
        continue
    fi
    sha=$(gh api "repos/datazuul/$repo/git/ref/heads/main" --jq .object.sha)
    for branch in develop release; do
        gh api "repos/datazuul/$repo/git/refs" -f ref="refs/heads/$branch" -f sha="$sha" >/dev/null
    done
    gh api -X PATCH "repos/datazuul/$repo" -f default_branch=develop >/dev/null
    # Rulesets need a public repository or a paid plan; without one the convention alone protects them.
    if ! gh api "repos/datazuul/$repo/rulesets" --input - >/dev/null <<'JSON'
{"name": "Release branches", "target": "branch", "enforcement": "active",
 "conditions": {"ref_name": {"include": ["refs/heads/main", "refs/heads/release"], "exclude": []}},
 "rules": [{"type": "non_fast_forward"}, {"type": "deletion"}]}
JSON
    then
        echo "  no ruleset (not available for this repository); main and release are not protected"
    fi
    echo "  develop and release at ${sha:0:10}, develop is the default branch"
done
