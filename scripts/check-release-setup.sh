#!/usr/bin/env bash
# Checks the release setup of the amadeOS repositories with the GitHub CLI (gh auth login): the settings and
# branches that setup-release-branches.sh makes. Each repository must have
#   - develop as its default branch,
#   - the branches develop and release,
#   - pull requests merged with merge commits only (no squash, no rebase),
#   - the active ruleset "Release branches" (main and release: fast-forward only, no deletion).
#
# Usage: scripts/check-release-setup.sh [--fix] [repository ...]
#
#   Without repositories: all of amadeos/repositories.list, then amadeos. Prints one line per repository,
#   "ok" or what is missing, and ends with exit status 1 if anything is missing.
#   --fix   also repairs what can be repaired safely: the default branch (when develop exists), the merge
#           settings and the ruleset. Missing develop or release branches are only reported: create them
#           with setup-release-branches.sh (for a repository without develop) or from main by hand.
set -euo pipefail

fix=0
if [ "${1:-}" = "--fix" ]; then
    fix=1
    shift
fi

if [ $# -gt 0 ]; then
    repos=("$@")
else
    mapfile -t repos < <(gh api repos/amadeos-eu/amadeos/contents/repositories.list -H 'Accept: application/vnd.github.raw' \
                             | sed -e 's/#.*//' -e '/^[[:space:]]*$/d' -e 's/[[:space:]]//g')
    repos+=(amadeos)
fi

RULESET='{"name": "Release branches", "target": "branch", "enforcement": "active",
 "conditions": {"ref_name": {"include": ["refs/heads/main", "refs/heads/release"], "exclude": []}},
 "rules": [{"type": "non_fast_forward"}, {"type": "deletion"}]}'

failed=0
width=0
for repo in "${repos[@]}"; do [ ${#repo} -gt $width ] && width=${#repo}; done

for repo in "${repos[@]}"; do
    problems=()
    fixed=()
    if ! settings=$(gh api "repos/amadeos-eu/$repo" \
            --jq '"\(.default_branch) \(.allow_merge_commit) \(.allow_squash_merge) \(.allow_rebase_merge)"' 2>/dev/null); then
        printf '%-*s  cannot be read (missing, or no access)\n' "$width" "$repo"
        failed=1
        continue
    fi
    read -r default merge squash rebase <<<"$settings"

    has_develop=1
    for branch in develop release; do
        if ! gh api "repos/amadeos-eu/$repo/branches/$branch" >/dev/null 2>&1; then
            problems+=("no $branch branch")
            [ "$branch" = develop ] && has_develop=0
        fi
    done

    if [ "$default" != develop ]; then
        if [ "$fix" = 1 ] && [ "$has_develop" = 1 ]; then
            gh api -X PATCH "repos/amadeos-eu/$repo" -f default_branch=develop >/dev/null
            fixed+=("default branch develop")
        else
            problems+=("default branch is $default")
        fi
    fi

    if [ "$merge $squash $rebase" != "true false false" ]; then
        if [ "$fix" = 1 ]; then
            gh api -X PATCH "repos/amadeos-eu/$repo" -F allow_merge_commit=true -F allow_squash_merge=false \
                -F allow_rebase_merge=false >/dev/null
            fixed+=("merge commits only")
        else
            problems+=("merge=$merge squash=$squash rebase=$rebase")
        fi
    fi

    ruleset=$(gh api "repos/amadeos-eu/$repo/rulesets" \
                  --jq '[.[] | select(.name == "Release branches") | .enforcement] | first // ""' 2>/dev/null || true)
    if [ "$ruleset" != active ]; then
        if [ "$fix" = 1 ] && [ -z "$ruleset" ] && gh api "repos/amadeos-eu/$repo/rulesets" --input - >/dev/null 2>&1 <<<"$RULESET"; then
            fixed+=("ruleset")
        elif [ -n "$ruleset" ]; then
            problems+=("ruleset \"Release branches\" is $ruleset")
        else
            problems+=("no ruleset \"Release branches\"")
        fi
    fi

    line="ok"
    if [ ${#problems[@]} -gt 0 ]; then
        failed=1
        line="$(IFS=';'; echo "${problems[*]}" | sed 's/;/; /g')"
    fi
    if [ ${#fixed[@]} -gt 0 ]; then
        line="$line (fixed: $(IFS=';'; echo "${fixed[*]}" | sed 's/;/, /g'))"
    fi
    printf '%-*s  %s\n' "$width" "$repo" "$line"
done

if [ "$failed" = 1 ]; then
    echo
    echo "Some repositories are not set up completely." >&2
    [ "$fix" = 1 ] || echo "Run again with --fix to repair the settings and the ruleset." >&2
fi
exit "$failed"
