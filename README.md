# amadeos-ci

Versions and releases for all amadeOS repositories: Semantic Versioning from 1.0.0, computed from
[Conventional Commits](https://www.conventionalcommits.org/), with the branches `develop` (builds
`X.Y.Z-dev.N`), `release` (`X.Y.Z-pre.N`) and `main` (releases: tag `vX.Y.Z` and a GitHub Release).
The whole workflow is explained in chapter 51, "Versions and Releases", of the
[Application Developer's Handbook](https://docs.amadeos.eu/amade-commons/51-releases/); the rules are
in `AGENTS.md` and `CONTRIBUTING.md` of [amadeos](https://github.com/amadeos-eu/amadeos).

This is its own repository because GitHub downloads a whole repository to run one of its actions, and
the amadeos repository has absolute symbolic links (the isolinux boot files) that break that download.

## Actions

Used by every repository's build workflow, from `main`:

| Action | Does |
|---|---|
| `amadeos-eu/amadeos-ci/version@main` | computes the version of the build (outputs `version`, `deb-version`, `channel`) and writes the `<releases>` of the given metainfo files |
| `amadeos-eu/amadeos-ci/release@main` | on main: tags `vX.Y.Z` and publishes a GitHub Release with release notes and the given files |
| `amadeos-eu/amadeos-ci/check-commits@main` | in pull requests: fails on commits that are no Conventional Commits |

All need a checkout with `fetch-depth: 0`. A change here reaches every repository at once, so
`scripts/test-ci.sh` tests the scripts in CI.

## Scripts

| Script | Does |
|---|---|
| `scripts/next-version.sh dev\|pre\|release` | the version of this build, from the commits since the last tag |
| `scripts/release-notes.sh [--xml] <from> <to>` | release notes grouped by commit type, Markdown or AppStream |
| `scripts/metainfo-releases.sh <file> <version>` | writes the `<releases>` of a metainfo file |
| `scripts/check-commits.sh <base> <head> [title]` | the Conventional Commits check |
| `scripts/promote.sh release\|main [repository ...]` | moves release up to develop or main up to release, by fast-forward |
| `scripts/setup-release-branches.sh [repository ...]` | one-time setup with `gh`: merge commits only, develop, release and the ruleset |
| `scripts/test-ci.sh` | tests all of them on throwaway repositories |

`buildDistribution.sh` of amadeos uses `next-version.sh` from a checkout of this repository next to it.

## Promote

*Actions → Promote → Run workflow*: "to" `release` or `main`, "repositories" empty for all of
`amadeos/repositories.list` (libraries first) plus amadeos. It needs the secret `PROMOTE_TOKEN`, an organization
secret of amadeos-eu shared with this repository: a fine-grained token with resource owner amadeos-eu for all
its repositories with *Contents* and *Workflows* read and write. The built-in token may neither push to other repositories nor push commits that change
workflow files, and its pushes would start no workflows.
The steps to create the token and the secret are in chapter 51 of the handbook,
["The token for Promote"](https://docs.amadeos.eu/amade-commons/51-releases/#the-token-for-promote).

This repository itself has only `main`; it is not promoted.

## Licence

EUPL-1.2
