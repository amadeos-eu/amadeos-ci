#!/usr/bin/env bash
# Writes the <releases> of an AppStream metainfo file from the release tags, so that Software shows
# what is new. CI runs it on the copy that goes into the package; the file in git has no <releases>.
#
# Usage: scripts/metainfo-releases.sh <metainfo.xml> <version>
#
# <version> is the version of this build (next-version.sh). A dev or pre build gets a first entry of
# type snapshot or development with the changes since the last tag; a release that is not tagged yet
# gets its entry with today's date. Then follow the last ten release tags with their changes.
# Versions are written the Debian way (1.1.0~dev.57), as the package has them.
set -euo pipefail

file=${1:?usage: metainfo-releases.sh <metainfo.xml> <version>}
version=${2:?usage: metainfo-releases.sh <metainfo.xml> <version>}
notes="$(dirname "${BASH_SOURCE[0]}")/release-notes.sh"

mapfile -t tags < <(git tag --list 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -rV || true)

# Writes one <release> with the changes between <from> and <to>.
release() {
    local version=$1 type=$2 date=$3 from=$4 to=$5 list
    list=$("$notes" --xml "$from" "$to")
    if [ -z "$list" ]; then
        printf '    <release version="%s" type="%s" date="%s"/>\n' "$version" "$type" "$date"
    else
        printf '    <release version="%s" type="%s" date="%s">\n' "$version" "$type" "$date"
        printf '      <description>\n'
        sed 's/^/        /' <<<"$list"
        printf '      </description>\n    </release>\n'
    fi
}

block=$(
    echo "  <releases>"
    case $version in
        *-dev.*) release "${version//-/\~}" snapshot "$(date -u +%F)" "${tags[0]:-}" HEAD ;;
        *-pre.*) release "${version//-/\~}" development "$(date -u +%F)" "${tags[0]:-}" HEAD ;;
        *) if ! printf '%s\n' "${tags[@]}" | grep -qx "v$version"; then
               release "$version" stable "$(date -u +%F)" "${tags[0]:-}" HEAD
           fi ;;
    esac
    for i in "${!tags[@]}"; do
        [ "$i" -ge 10 ] && break
        release "${tags[$i]#v}" stable "$(git log -1 --format=%cs "${tags[$i]}")" "${tags[$((i + 1))]:-}" "${tags[$i]}"
    done
    echo "  </releases>"
)

# Replace an existing <releases> element, or add one before </component>.
BLOCK=$block awk '
    /<releases[ >]/ { skip = 1 }
    skip && /<\/releases>/ { skip = 0; next }
    skip { next }
    /<\/component>/ { print ENVIRON["BLOCK"] }
    { print }
' "$file" > "$file.tmp"
mv "$file.tmp" "$file"
