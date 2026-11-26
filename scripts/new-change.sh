#!/usr/bin/env bash
# Create a change branch + worktree based on the mirror master.
# usage: new-change.sh feat|fix <slug>
set -euo pipefail
kind="${1:?usage: new-change.sh feat|fix <slug>}"
slug="${2:?usage: new-change.sh feat|fix <slug>}"
case "$kind" in feat|fix) ;; *) echo "kind must be 'feat' or 'fix'" >&2; exit 2 ;; esac

REPO="${CARTOGRAPHY_REPO:-$HOME/repos/cartography-work}"
branch="$kind/$slug"
wt="$HOME/repos/wt-$slug"

cd "$REPO"
git fetch --quiet upstream && git fetch --quiet origin
if git show-ref --verify --quiet "refs/heads/$branch"; then
  echo "branch $branch already exists" >&2; exit 1
fi
if [ -e "$wt" ]; then
  echo "worktree path $wt already exists" >&2; exit 1
fi

git worktree add --quiet -b "$branch" "$wt" origin/master
uv venv "$wt/.venv" --python 3.13 >/dev/null
uv pip install --quiet --python "$wt/.venv/bin/python" -e "$wt[neo4j]" \
  pytest ruff pytest-cov pytest-mock pytest-asyncio >/dev/null

echo "branch   : $branch"
echo "based on : $(git rev-parse --short origin/master)  ($(git describe --tags origin/master 2>/dev/null || echo untagged))"
echo "worktree : $wt"
echo
echo "next:"
echo "  cd $wt"
echo "  PYTHONPATH=\$PWD .venv/bin/python -c 'import cartography; print(cartography.__file__)'"
echo "  # assert the path above is inside $wt BEFORE editing anything"
