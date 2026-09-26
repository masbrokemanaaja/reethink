#!/bin/sh
# Publish the GitHub release for the version install.sh declares, once.
#
# .github/workflows/release.yml runs this on every push to main, so a release
# is the merge of a version bump and nothing more: `tools/version.py set` in a
# pull request, merge it, and the tag and the release page follow. A push that
# did not change the version finds its tag already there and does nothing.
#
# The release body is the changelog section `tools/version.py notes` prints,
# never a list of commit subjects, and a version with a hyphen (1.2.0-rc.1)
# is published as a prerelease.
#
#   sh tools/release.sh             publish if the version has no tag yet
#   sh tools/release.sh --pending   print true or false, publish nothing
#   sh tools/release.sh --dry-run   print the gh command, publish nothing
#
# Needs git, python3, and gh with a token that may write releases.
#
# reethink, by ree_es97 (https://reetech.web.id)
# MIT licensed. https://github.com/masbrokemanaaja/reethink

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
MODE="publish"
case "${1:-}" in
  "") ;;
  --pending) MODE="pending" ;;
  --dry-run) MODE="dry-run" ;;
  *) echo "usage: sh tools/release.sh [--pending | --dry-run]" >&2; exit 2 ;;
esac

V=$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$ROOT/install.sh")
if [ -z "$V" ]; then
  echo "release: install.sh has no VERSION line" >&2
  exit 1
fi
TAG="v$V"

# The tag is the record that a version was released. It is read locally, so
# the checkout has to carry tags (fetch-depth: 0 in the workflow).
if git -C "$ROOT" rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  if [ "$MODE" = "pending" ]; then echo false; else echo "release: $TAG already exists, nothing to publish"; fi
  exit 0
fi
if [ "$MODE" = "pending" ]; then
  echo true
  exit 0
fi

# Every site has to hold this version and the changelog has to name it, or
# the release would describe a package that does not exist.
python3 "$ROOT/tools/version.py" check

notes=$(mktemp)
trap 'rm -f "$notes"' EXIT INT TERM
python3 "$ROOT/tools/version.py" notes "$V" > "$notes"

sha=$(git -C "$ROOT" rev-parse HEAD)
set -- "$TAG" --target "$sha" --title "reethink $V" --notes-file "$notes"
case "$V" in
  *-*) set -- "$@" --prerelease ;;
esac

if [ "$MODE" = "dry-run" ]; then
  echo "release: would run gh release create $*"
  exit 0
fi
gh release create "$@"
echo "release: published $TAG at $sha"
