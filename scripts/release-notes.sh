#!/usr/bin/env bash
# Prints the changes between two commits as release notes, grouped by Conventional Commit type.
#
# Usage: scripts/release-notes.sh [--xml] <from> <to>
#
#   <from>  the previous release tag, or "" for the whole history up to <to>
#   <to>    a tag or commit, usually HEAD
#
# Markdown for a GitHub Release; with --xml an AppStream <ul> for the <description> of a metainfo
# <release> (nothing when there are no changes to show). ci, chore, test, style and build commits are
# left out, and so are commits that are no Conventional Commits (the history before the first release).
set -euo pipefail

xml=0
if [ "${1:-}" = --xml ]; then xml=1; shift; fi
from=$1 to=$2
range=$to
[ -n "$from" ] && range="$from..$to"

escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

breaking=() features=() fixes=() other=()
pattern='^([a-z]+)(\(([^)]*)\))?(!)?: (.+)$'
while IFS= read -r -d '' commit; do
    commit=${commit#$'\n'}
    subject=${commit%%$'\n'*}
    [[ $subject =~ $pattern ]] || continue
    type=${BASH_REMATCH[1]} scope=${BASH_REMATCH[3]} bang=${BASH_REMATCH[4]} text=${BASH_REMATCH[5]}
    if [ "$xml" = 1 ]; then
        line=${scope:+$scope: }$text
    else
        line=${scope:+**$scope:** }$text
    fi
    if [ -n "$bang" ] || grep -qE '^BREAKING[ -]CHANGE: ' <<<"$commit"; then
        breaking+=("$line")
    else
        case $type in
            feat) features+=("$line") ;;
            fix|perf) fixes+=("$line") ;;
            docs|refactor|revert) other+=("$line") ;;
        esac
    fi
done < <(git log --no-merges --format='%s%n%b%x00' "$range")

if [ "$xml" = 1 ]; then
    all=("${breaking[@]}" "${features[@]}" "${fixes[@]}" "${other[@]}")
    [ ${#all[@]} -eq 0 ] && exit 0
    echo "<ul>"
    for line in "${all[@]}"; do printf '  <li>%s</li>\n' "$(escape <<<"$line")"; done
    echo "</ul>"
    exit 0
fi

section() {
    local title=$1; shift
    [ $# -eq 0 ] && return
    printf '## %s\n\n' "$title"
    printf -- '- %s\n' "$@"
    echo
}
section "Breaking changes" "${breaking[@]}"
section "Features" "${features[@]}"
section "Fixes" "${fixes[@]}"
section "Other changes" "${other[@]}"
if [ $(( ${#breaking[@]} + ${#features[@]} + ${#fixes[@]} + ${#other[@]} )) -eq 0 ]; then
    echo "Maintenance release without user-visible changes."
fi
