#!/usr/bin/env bash
# Tests the version and release scripts of scripts/ on throwaway repositories.
#
# Usage: scripts/test-ci.sh
set -euo pipefail

scripts=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

expect() {
    local what=$1 expected=$2 actual=$3
    if [ "$expected" = "$actual" ]; then
        echo "ok    $what: $actual"
    else
        echo "FAIL  $what: expected '$expected', got '$actual'"
        failures=$((failures + 1))
    fi
}
commit() { git -c user.name=Test -c user.email=test@example.org commit --quiet --allow-empty -m "$1"; }
version() { GITHUB_RUN_NUMBER=${2:-7} "$scripts/next-version.sh" "$1" 2>/dev/null || echo "error"; }

cd "$work"
git init --quiet repo
cd repo
commit "Front panel: battery cell"

expect "no tag, dev" "1.0.0-dev.7" "$(version dev)"
expect "no tag, pre" "1.0.0-pre.8" "$(version pre 8)"
expect "no tag, release" "1.0.0" "$(version release)"
expect "local build" "1.0.0-dev.0" "$(GITHUB_RUN_NUMBER='' "$scripts/next-version.sh" dev)"

git tag v1.0.0
expect "rebuild of the tagged commit" "1.0.0" "$(version release)"
expect "nothing new, dev" "1.0.0-dev.7" "$(version dev)"
commit "Merge branch 'release' into develop"
expect "only old-style commits count as patch" "1.0.1" "$(version release)"

git tag v1.0.1
commit "fix(wm): closing a dialog activates its owner"
commit "docs(handbook): chapter 51"
expect "fix" "1.0.2-pre.9" "$(version pre 9)"
commit "feat(panel): sound cell"
expect "feat" "1.1.0-dev.10" "$(version dev 10)"
commit "feat(settings)!: one settings file"
expect "breaking with !" "2.0.0" "$(version release)"

git tag v2.0.0
commit "$(printf 'refactor(base): new reader\n\nBREAKING CHANGE: the old format is gone')"
expect "breaking change footer" "3.0.0" "$(version release)"
git tag v2.0.0-pre.3
expect "pre tags are not release tags" "3.0.0" "$(version release)"

notes=$("$scripts/release-notes.sh" v1.0.1 v2.0.0)
expect "notes: breaking first" "## Breaking changes" "$(head -1 <<<"$notes")"
expect "notes: feature with scope" "- **panel:** sound cell" "$(grep -F 'sound cell' <<<"$notes")"
expect "notes: no old-style commits" "" "$(grep -F 'Front panel' <<<"$notes" || true)"
expect "notes: empty release" "Maintenance release without user-visible changes." "$("$scripts/release-notes.sh" v1.0.0 v1.0.1)"
commit "fix(mail): <b> & friends"
expect "xml notes are escaped" "  <li>mail: &lt;b&gt; &amp; friends</li>" "$("$scripts/release-notes.sh" --xml v2.0.0 HEAD | grep mail)"

cat > app.metainfo.xml <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>eu.amadeos.apps.test</id>
  <releases>
    <release version="0.1.0" date="2026-01-01"/>
  </releases>
</component>
XML
"$scripts/metainfo-releases.sh" app.metainfo.xml 3.0.0-dev.12
expect "metainfo: snapshot first" '<release version="3.0.0~dev.12" type="snapshot"' \
    "$(grep -m1 -o '<release version="[^"]*" type="[a-z]*"' app.metainfo.xml)"
expect "metainfo: old releases replaced" "" "$(grep -F 0.1.0 app.metainfo.xml || true)"
expect "metainfo: one releases element" "1" "$(grep -c '<releases>' app.metainfo.xml)"
expect "metainfo: tags listed" "3" "$(grep -c 'type="stable"' app.metainfo.xml)"
"$scripts/metainfo-releases.sh" app.metainfo.xml 3.0.0
expect "metainfo: untagged release first" '<release version="3.0.0" type="stable"' \
    "$(grep -m1 -o '<release version="[^"]*" type="[a-z]*"' app.metainfo.xml)"
if command -v xmllint >/dev/null; then
    xmllint --noout app.metainfo.xml && echo "ok    metainfo is well-formed XML"
fi

if "$scripts/check-commits.sh" v1.0.0 v1.0.1 >/dev/null; then
    echo "FAIL  check-commits accepts a Conventional Commit range"; failures=$((failures + 1))
else
    echo "ok    check-commits rejects the old-style history"
fi
commit "feat(pad): word count"
"$scripts/check-commits.sh" HEAD~1 HEAD "fix(pad): title" >/dev/null && echo "ok    check-commits accepts feat(pad)" \
    || { echo "FAIL  check-commits rejects feat(pad)"; failures=$((failures + 1)); }
"$scripts/check-commits.sh" HEAD~1 HEAD "Pad: title" >/dev/null \
    && { echo "FAIL  check-commits accepts the title 'Pad: title'"; failures=$((failures + 1)); } \
    || echo "ok    check-commits rejects the title 'Pad: title'"

# promote.sh on local bare repositories: a library with a release, an app that pins it.
cd "$work"
for name in amade-commons amade-test; do
    git init --quiet "$name-src"
    (cd "$name-src" && commit "feat: start" && git branch -M main && git branch develop && git branch release)
    git clone --quiet --bare "$name-src" "remote/$name.git"
done
git -C remote/amade-commons.git tag v1.0.0 main
git clone --quiet remote/amade-test.git app
cd app
git switch --quiet develop
echo "implementation 'com.github.amadeos-eu:amade-commons:abc1234567'" > build.gradle
git add build.gradle && commit "feat(test): uses commons"
git push --quiet origin develop
promote() { PROMOTE_TOKEN='' GITHUB_TOKEN='' PROMOTE_REMOTE="$work/remote" "$scripts/promote.sh" "$@" >"$work/promote.log" 2>&1; }
promote release amade-test && promoted=yes || promoted=no
expect "promote to release" "yes" "$promoted"
expect "release is develop" "$(git rev-parse origin/develop)" "$(git ls-remote origin refs/heads/release | cut -f1)"
promote main amade-test && promoted=yes || promoted=no
expect "main refuses an unreleased commons pin" "no" "$promoted"
sed -i 's/abc1234567/v1.0.0/' build.gradle
git add build.gradle && commit "build(deps): amade-commons v1.0.0"
git push --quiet origin develop
promote release amade-test && promote main amade-test && promoted=yes || promoted=no
expect "promote to main with a released pin" "yes" "$promoted"
expect "main is develop" "$(git rev-parse HEAD)" "$(git ls-remote origin refs/heads/main | cut -f1)"
# A hotfix merged into release is merged back into develop.
git fetch --quiet origin
git switch --quiet -c hotfix origin/release
commit "fix(test): hotfix"
git switch --quiet develop && commit "feat(test): unfinished work" && git push --quiet origin develop
git push --quiet origin hotfix:release
promote main amade-test && promoted=yes || promoted=no
expect "promote the hotfix" "yes" "$promoted"
git fetch --quiet origin
git merge-base --is-ancestor origin/main origin/develop && merged=yes || merged=no
expect "hotfix is back on develop" "yes" "$merged"
promote release amade-test && promoted=yes || promoted=no
expect "release moves on after the hotfix" "yes" "$promoted"

# Without repositories: the list of amadeos, then amadeos itself (which has no develop here, so it is skipped).
git init --quiet "$work/amadeos-src"
(cd "$work/amadeos-src" && printf '# Applications\namade-test\n' > repositories.list && git add repositories.list \
    && commit "chore: list" && git branch -M main)
git clone --quiet --bare "$work/amadeos-src" "$work/remote/amadeos.git"
promote release && promoted=yes || promoted=no
expect "promote all of repositories.list" "yes" "$promoted"
expect "repositories.list is read" "2" "$(grep -cE '^== (amade-test|amadeos)$' "$work/promote.log")"

if [ "$failures" -gt 0 ]; then
    echo "$failures failure(s)"
    exit 1
fi
echo "All checks passed."
