#!/usr/bin/env bash
# Shows the result of the Build workflow for the current head of a branch in every amadeOS repository, with the
# GitHub CLI (gh auth login). Use it after a Promote to see whether all release or main builds are done and green.
#
# Usage: scripts/check-builds.sh [develop|release|main] [repository ...]
#
#   Branch: default release. Without repositories: all of amadeos/repositories.list, then amadeos.
#   Prints one line per repository: "success", "running", "queued", "failure" (with the link to the run),
#   or "no build" when no Build run exists for the branch head yet (right after a Promote, or for a
#   repository whose branch did not move). On main, a green line also shows the newest release tag.
#   Exit status 0 when every build is green, 1 when one failed, 2 when one is still running or missing.
set -euo pipefail

branch=release
case "${1:-}" in
    develop|release|main) branch=$1; shift ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

if [ $# -gt 0 ]; then
    repos=("$@")
else
    mapfile -t repos < <(gh api repos/amadeos-eu/amadeos/contents/repositories.list -H 'Accept: application/vnd.github.raw' \
                             | sed -e 's/#.*//' -e '/^[[:space:]]*$/d' -e 's/[[:space:]]//g')
    repos+=(amadeos)
fi

width=0
for repo in "${repos[@]}"; do [ ${#repo} -gt $width ] && width=${#repo}; done

red=0
open=0
for repo in "${repos[@]}"; do
    if ! sha=$(gh api "repos/amadeos-eu/$repo/branches/$branch" --jq .commit.sha 2>/dev/null); then
        printf '%-*s  no %s branch (or no access)\n' "$width" "$repo" "$branch"
        red=1
        continue
    fi
    run=$(gh api "repos/amadeos-eu/$repo/actions/runs?branch=$branch&head_sha=$sha&per_page=20" \
              --jq '[.workflow_runs[] | select(.name == "Build")] | first
                    | if . == null then "" else "\(.status) \(.conclusion // "-") \(.html_url)" end')
    short=${sha:0:7}
    if [ -z "$run" ]; then
        printf '%-*s  no build    %s\n' "$width" "$repo" "$short"
        open=1
        continue
    fi
    read -r status conclusion url <<<"$run"
    if [ "$status" != completed ]; then
        [ "$status" = in_progress ] && status=running
        printf '%-*s  %-10s  %s  %s\n' "$width" "$repo" "$status" "$short" "$url"
        open=1
    elif [ "$conclusion" = success ]; then
        extra=""
        if [ "$branch" = main ]; then
            extra=$(gh api "repos/amadeos-eu/$repo/releases/latest" --jq .tag_name 2>/dev/null || true)
        fi
        printf '%-*s  %-10s  %s  %s\n' "$width" "$repo" success "$short" "$extra"
    else
        printf '%-*s  %-10s  %s  %s\n' "$width" "$repo" "$conclusion" "$short" "$url"
        red=1
    fi
done

if [ "$red" = 1 ]; then
    echo
    echo "Some builds failed: open the link, \"Re-run failed jobs\" (often a Windows or network hiccup)." >&2
    exit 1
fi
if [ "$open" = 1 ]; then
    echo
    echo "Some builds are still running or have not started yet. Run again in a few minutes." >&2
    exit 2
fi
echo
echo "All $branch builds are green."
