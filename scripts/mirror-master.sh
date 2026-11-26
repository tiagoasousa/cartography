#!/usr/bin/env bash
# Fast-forward local master to upstream/master and push it to the fork.
# Fails hard if master carries ANY local commit: master is a strict 1:1 mirror.
set -euo pipefail
REPO="${CARTOGRAPHY_REPO:-$HOME/repos/cartography-work}"
cd "$REPO"

git fetch --prune --quiet upstream
git fetch --prune --quiet origin

ahead=$(git rev-list --count upstream/master..master)
if [ "$ahead" -ne 0 ]; then
  echo "REFUSING: master has $ahead commit(s) not in upstream:" >&2
  git log --oneline upstream/master..master >&2
  echo "master must mirror upstream. Move that work to a feat/* branch, then reset master." >&2
  exit 1
fi

git checkout --quiet master
git merge --ff-only --quiet upstream/master

before=$(git rev-parse origin/master)
ALLOW_MASTER_PUSH=1 git push --quiet origin master
git fetch --quiet origin
after=$(git rev-parse origin/master)

if [ "$before" = "$after" ]; then
  echo "master unchanged: ${after:0:8}"
else
  echo "master ${before:0:8} -> ${after:0:8} ($(git rev-list --count "$before..$after") commits)"
fi
echo "tag: $(git describe --tags origin/master 2>/dev/null || echo none)"
