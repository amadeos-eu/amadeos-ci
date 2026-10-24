#!/usr/bin/env bash
# Promotes repositories: moves release up to develop (a pre build for testing) or main up to release
# (the release: CI tags vX.Y.Z and publishes a GitHub Release). Both moves are fast-forwards, so the
# three branches hold the same commits. Runs in the Promote workflow of this repository, or on your machine.
#
# Usage: scripts/promote.sh release|main [repository ...]
#
#   Without repositories: all of amadeos/repositories.list in its order (libraries first), then amadeos.
#   GITHUB_TOKEN or PROMOTE_TOKEN: a token that may push to the repositories, workflow files included
#   (a fine-grained token with Contents and Workflows read and write). Without one, git uses your own
#   credentials. PROMOTE_REMOTE replaces https://github.com/datazuul (for tests).
#
# Before main is moved, the pins of amade-commons and amade-game-engine in build.gradle must be
# released versions (a tag vX.Y.Z, or a commit that a release tag contains), and the libraries are
# released first: their main is moved and the script waits until CI has tagged it.
# After a hotfix that went into release directly, main is merged back into develop.
set -euo pipefail

to=${1:?usage: promote.sh release|main [repository ...]}
shift
case $to in
    release) from=develop ;;
    main) from=release ;;
    *) echo "promote.sh: promote to release or main, not $to" >&2; exit 2 ;;
esac

token=${PROMOTE_TOKEN:-${GITHUB_TOKEN:-}}
libraries=(amade-commons amade-game-engine)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

url() {
    if [ -n "$token" ]; then
        echo "https://x-access-token:$token@github.com/datazuul/$1.git"
    else
        echo "${PROMOTE_REMOTE:-https://github.com/datazuul}/$1.git"
    fi
}

# A clone without file contents; git fetches the few files the checks read on demand.
clone() {
    [ -d "$work/$1" ] || git clone --quiet --filter=blob:none --no-checkout "$(url "$1")" "$work/$1"
}

if [ $# -gt 0 ]; then
    repos=("$@")
else
    # The list on the default branch of amadeos.
    clone amadeos
    mapfile -t repos < <(git -C "$work/amadeos" show origin/HEAD:repositories.list \
                             | sed -e 's/#.*//' -e '/^[[:space:]]*$/d' -e 's/[[:space:]]//g')
    repos+=(amadeos)
fi

stable_tags() { git -C "$work/$1" tag --list 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || true; }

# Fails when a library pin of <repo> on <branch> is not a released version.
check_pins() {
    local repo=$1 branch=$2 lib ref ok=1
    while IFS=: read -r _ lib ref; do
        clone "$lib"
        git -C "$work/$lib" fetch --quiet --tags origin
        if [[ $ref =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            stable_tags "$lib" | grep -qx "$ref" && continue
            echo "  $repo pins $lib $ref, which does not exist" >&2
        elif git -C "$work/$lib" tag --contains "$ref" 2>/dev/null | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
            continue
        else
            echo "  $repo pins $lib at $ref, which is in no release of $lib yet." >&2
            echo "  Release $lib first and pin its tag (com.github.datazuul:$lib:vX.Y.Z)." >&2
        fi
        ok=0
    done < <(git -C "$work/$repo" grep -hoE "com\.github\.datazuul:amade-(commons|game-engine):[A-Za-z0-9._-]+" \
                 "origin/$branch" -- '*.gradle' | sort -u)
    [ "$ok" = 1 ]
}

# Waits until CI has tagged <sha> of <repo> with a release tag (at most 40 minutes).
wait_for_tag() {
    local repo=$1 sha=$2 i tag
    for i in $(seq 120); do
        tag=$(git ls-remote --tags "$(url "$repo")" 'v*' \
                | awk -v sha="$sha" '$1 == sha { sub("refs/tags/", "", $2); sub("\\^\\{\\}", "", $2); print $2 }' \
                | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true)
        if [ -n "$tag" ]; then echo "  $repo is released as $tag"; return 0; fi
        sleep 20
    done
    echo "  $repo: no release tag on main after 40 minutes; check its Build workflow" >&2
    return 1
}

failed=()
for repo in "${repos[@]}"; do
    echo "== $repo"
    clone "$repo"
    git -C "$work/$repo" fetch --quiet --tags origin
    if ! git -C "$work/$repo" rev-parse --verify --quiet "origin/$from" >/dev/null \
        || ! git -C "$work/$repo" rev-parse --verify --quiet "origin/$to" >/dev/null; then
        echo "  no $from or $to branch yet (see scripts/setup-release-branches.sh); skipped"
        continue
    fi
    source_sha=$(git -C "$work/$repo" rev-parse "origin/$from")
    if [ "$source_sha" = "$(git -C "$work/$repo" rev-parse "origin/$to")" ]; then
        echo "  $to is up to date"
        continue
    fi
    if ! git -C "$work/$repo" merge-base --is-ancestor "origin/$to" "origin/$from"; then
        echo "  $to has commits that $from lacks; merge $to into $from first" >&2
        failed+=("$repo"); continue
    fi
    if [ "$to" = main ] && ! check_pins "$repo" "$from"; then
        failed+=("$repo"); continue
    fi
    git -C "$work/$repo" log --oneline --no-merges "origin/$to..origin/$from" | sed 's/^/  /'
    git -C "$work/$repo" push --quiet origin "$source_sha:refs/heads/$to"
    echo "  $to moved to ${source_sha:0:10}"

    if [ "$to" = main ]; then
        # A hotfix merged into release is not on develop yet: bring it back.
        if ! git -C "$work/$repo" merge-base --is-ancestor "$source_sha" origin/develop; then
            git -C "$work/$repo" checkout --quiet -B develop origin/develop
            if git -C "$work/$repo" -c user.name="amadeOS release" -c user.email=developers@datazuul.com \
                   merge --quiet --no-ff -m "chore(release): merge the release back into develop" "$source_sha"; then
                git -C "$work/$repo" push --quiet origin develop
                echo "  merged main back into develop"
            else
                echo "  merging main back into develop has conflicts; do it by hand" >&2
                failed+=("$repo")
            fi
        fi
        if [[ " ${libraries[*]} " == *" $repo "* ]] && ! wait_for_tag "$repo" "$source_sha"; then
            failed+=("$repo")
            echo "Stopping: the repositories after $repo may pin it." >&2
            break
        fi
    fi
done

if [ ${#failed[@]} -gt 0 ]; then
    echo "Not promoted: ${failed[*]}" >&2
    exit 1
fi
