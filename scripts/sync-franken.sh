#!/usr/bin/env bash
# Move franken-master onto a newer upstream master, without touching `master`.
#
# Pushes a one-line bump of .github/franken/upstream-ref on top of franken-master.
# That push starts .github/workflows/sync_franken.yml, which rebases the 23-patch
# stack onto the named upstream commit, verifies the result against
# franken.manifest, and pushes the rebased branch. The workflow deletes the bump
# file, so franken-master ends up equal to master + franken.manifest again.
#
# The fork's `master` is NOT used as the rebase base and is NOT modified: it only
# advances when mirror-master.sh runs. A named upstream commit that is behind the
# mirror is reported as drift by the workflow and nothing is pushed.
#
# Usage:
#   sync-franken.sh              # use the current upstream/master tip
#   sync-franken.sh <sha|ref>    # use a specific upstream commit
set -euo pipefail
OPS="${CARTOGRAPHY_OPS:-$HOME/repos/cartography-ops}"
REPO="${CARTOGRAPHY_REPO:-$HOME/repos/cartography-work}"
cd "$REPO"

git fetch --prune --quiet upstream
git fetch --prune --quiet origin

target="${1:-upstream/master}"
want=$(git rev-parse --verify --quiet "${target}^{commit}") || {
  echo "REFUSING: $target is not a commit (fetch first?)" >&2; exit 1
}

if ! git merge-base --is-ancestor "$want" refs/remotes/upstream/master; then
  echo "REFUSING: $want is not on upstream master." >&2
  echo "Only a commit on upstream master can be a rebase base for franken-master." >&2
  exit 1
fi

mirror=$(git rev-parse origin/master)
current=$(git rev-parse origin/franken-master)

if [ "$want" = "$mirror" ]; then
  echo "nothing to do: upstream tip $want is already the fork mirror"
  exit 0
fi
if git merge-base --is-ancestor "$want" "$mirror"; then
  echo "REFUSING: $want is BEHIND the fork mirror $mirror." >&2
  echo "master already mirrors a newer upstream, and every open PR is based on it." >&2
  echo "Rewinding franken-master would strand them. Nothing to sync." >&2
  exit 1
fi

if [ -n "$(git status --porcelain | grep -v '^??')" ]; then
  echo "REFUSING: working tree has uncommitted changes" >&2; exit 1
fi

echo "upstream tip : $want"
echo "fork mirror  : $mirror"
echo "franken-master: $current"
echo

# Branch off the published franken-master, never off a local one that may be
# ahead of what CI has actually seen.
git checkout --quiet --detach origin/franken-master
mkdir -p .github/franken
git show "$current:.github/workflows/sync_franken.yml" >/dev/null 2>&1 || {
  echo "REFUSING: sync_franken.yml is not on franken-master yet." >&2
  echo "The bump push would not start the workflow. Ship the workflow first." >&2
  exit 1
}
{
  echo "# Upstream commit franken-master is rebuilt onto."
  echo "# Written by cartography-ops/scripts/sync-franken.sh - do not edit by hand."
  echo "#"
  echo "# Pushing a change to THIS file starts .github/workflows/sync_franken.yml,"
  echo "# which rebases franken-master onto the SHA below and then deletes this file."
  echo "# This is a trigger, not a build input: the workflow fetches the SHA from"
  echo "# cartography-cncf/cartography, so it must be a commit on upstream master."
  echo "$want"
} > .github/franken/upstream-ref

git add .github/franken/upstream-ref
git commit --quiet -s -m "chore: rebuild franken-master onto upstream ${want:0:8}

Bump .github/franken/upstream-ref to start the rebase workflow. The file is
deleted by the run, so this commit does not persist in the rebuilt branch."

echo
echo "pushing the bump to origin/franken-master ..."
git push --quiet origin HEAD:refs/heads/franken-master

echo "pushed. The rebase workflow is now running:"
echo "  gh run list --repo ${CARTOGRAPHY_SLUG:-tiagoasousa/cartography} --workflow sync_franken.yml --limit 1"
echo
echo "When it finishes, bump ci/cartography-ref.env in cartography-assistant to the"
echo "new franken-master tip (manual, by design)."
