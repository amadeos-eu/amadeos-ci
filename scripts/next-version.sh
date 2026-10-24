#!/usr/bin/env bash
# Prints the version of this build, computed from the Conventional Commits since the last release tag.
#
# Usage: scripts/next-version.sh dev|pre|release   (inside the repository, with full history and tags)
#
#   dev      1.1.0-dev.<build>   develop, pull requests, local builds (build 0)
#   pre      1.1.0-pre.<build>   release
#   release  1.1.0               main
#
# <build> is GITHUB_RUN_NUMBER, 0 outside CI. A repository without a release tag starts at 1.0.0.
# Since the last tag vX.Y.Z a breaking change (type!: or a BREAKING CHANGE footer) raises the major
# version, a feat the minor version and every other commit the patch version. Merge commits do not count.
# Debian packages use the same version with ~ instead of - (1.1.0~dev.57 < 1.1.0~pre.61 < 1.1.0).
set -euo pipefail

channel=${1:?usage: next-version.sh dev|pre|release}
build=${GITHUB_RUN_NUMBER:-0}

last=$(git tag --list 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1 || true)
if [ -z "$last" ]; then
    next=1.0.0
else
    IFS=. read -r major minor patch <<<"${last#v}"
    log=$(git log --no-merges --format='%s%n%b' "$last..HEAD")
    if grep -qE '^[a-z]+(\([^)]*\))?!: |^BREAKING[ -]CHANGE: ' <<<"$log"; then
        next=$((major + 1)).0.0
    elif grep -qE '^feat(\([^)]*\))?: ' <<<"$log"; then
        next=$major.$((minor + 1)).0
    elif [ -n "$log" ]; then
        next=$major.$minor.$((patch + 1))
    else
        next=""  # nothing new since the last release
    fi
fi

case $channel in
    dev) echo "${next:-${last#v}}-dev.$build" ;;
    pre) echo "${next:-${last#v}}-pre.$build" ;;
    release)
        if [ -n "$next" ]; then
            echo "$next"
        elif git tag --points-at HEAD | grep -qx "$last"; then
            echo "${last#v}"  # a rebuild of the released commit
        else
            echo "next-version.sh: no commit since $last, nothing to release" >&2
            exit 1
        fi
        ;;
    *) echo "next-version.sh: unknown channel $channel (dev, pre or release)" >&2; exit 2 ;;
esac
