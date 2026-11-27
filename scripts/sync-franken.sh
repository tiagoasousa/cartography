#!/usr/bin/env bash
# Move franken-master onto newer upstream master, keeping master a strict mirror.
#
# Starts .github/workflows/sync_franken.yml, which advances the fork's `master` to
# the upstream commit and rebases the franken-master stack onto it, then pushes
# both. The invariant it maintains is franken-master == master + franken.manifest.
#
# Nothing here pushes a branch directly, so a conflict never leaves the two refs
# out of step: the workflow verifies the replay before it pushes anything.
#
# Usage:
#   sync-franken.sh                 # move to the current upstream master tip
#   sync-franken.sh <sha>           # move to a specific upstream commit
#   sync-franken.sh --dry-run       # report what would change, push nothing
set -euo pipefail
OPS="${CARTOGRAPHY_OPS:-$HOME/repos/cartography-ops}"
REPO="${CARTOGRAPHY_REPO:-$HOME/repos/cartography-work}"
SLUG="${CARTOGRAPHY_SLUG:-tiagoasousa/cartography}"
cd "$REPO"

dry_run=false
target=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=true ;;
    -*) echo "unknown option: $arg" >&2; exit 2 ;;
    *) target="$arg" ;;
  esac
done

git fetch --prune --quiet upstream
git fetch --prune --quiet origin

want=$(git rev-parse --verify --quiet "${target:-upstream/master}^{commit}") || {
  echo "REFUSING: ${target:-upstream/master} is not a commit (fetch first?)" >&2; exit 1
}
if ! git merge-base --is-ancestor "$want" refs/remotes/upstream/master; then
  echo "REFUSING: $want is not on upstream master." >&2
  echo "Only a commit on upstream master is a valid target." >&2
  exit 1
fi

mirror=$(git rev-parse origin/master)
branch=$(git rev-parse origin/franken-master)

if [ "$want" = "$mirror" ]; then
  echo "nothing to do: fork master already mirrors $want"
  exit 0
fi
if git merge-base --is-ancestor "$want" "$mirror"; then
  echo "nothing to do: $want is behind the fork mirror $mirror."
  echo "The mirror already contains newer upstream, so there is nothing to advance to."
  exit 0
fi
if ! git merge-base --is-ancestor "$mirror" "$want"; then
  echo "REFUSING: the fork mirror $mirror has diverged from upstream." >&2
  echo "master is only legitimate as a strict 1:1 mirror. Resolve by hand:" >&2
  echo "  git log --oneline $want..$mirror    # commits master has that upstream does not" >&2
  exit 1
fi

echo "upstream target: $want ($(git log -1 --format=%s "$want"))"
echo "fork master    : $mirror -> $want ($(git rev-list --count "$mirror..$want") commits)"
echo "franken-master : $branch"
echo

if [ "$dry_run" = true ]; then
  echo "dry run: would advance master to ${want:0:8} and rebase franken-master onto it."
  echo "Nothing pushed. Re-run without --dry-run to apply."
  exit 0
fi

echo "starting the rebase workflow ..."
gh workflow run sync_franken.yml --repo "$SLUG" --ref franken-master -f upstream_sha="$want"

# Wait for the run it just started, not whatever was already in flight.
sleep 5
run_id=$(gh run list --repo "$SLUG" --workflow sync_franken.yml --limit 1 \
  --json databaseId,event --jq '[.[] | select(.event=="workflow_dispatch")][0].databaseId')
if [ -z "$run_id" ] || [ "$run_id" = "null" ]; then
  echo "could not find the dispatched run; check the Actions tab." >&2
  exit 1
fi
echo "run $run_id:"
gh run watch "$run_id" --repo "$SLUG" --exit-status || {
  echo "" >&2
  echo "the rebase failed - both branches are unchanged." >&2
  echo "gh run view $run_id --repo $SLUG --log-failed" >&2
  exit 1
}

git fetch --quiet origin
new_branch=$(git rev-parse origin/franken-master)
echo
echo "franken-master: $new_branch"
echo "master        : $(git rev-parse origin/master)"
echo
echo "Next: bump ci/cartography-ref.env in cartography-assistant to ${new_branch:0:8}"
echo "(manual, by design)."
