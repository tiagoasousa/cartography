#!/usr/bin/env bash
# Is a change branch PR-ready? usage: check-branch.sh [--max-commits N] <branch>
set -uo pipefail
max=5
if [ "${1:-}" = "--max-commits" ]; then max="$2"; shift 2; fi
branch="${1:?usage: check-branch.sh [--max-commits N] <branch>}"
REPO="${CARTOGRAPHY_REPO:-$HOME/repos/cartography-work}"
cd "$REPO" || exit 2

fail=0
note() { printf '  %-9s %s\n' "$1" "$2"; }

git rev-parse --verify -q "$branch" >/dev/null || { echo "  FAIL no such branch: $branch"; exit 2; }

n=$(git rev-list --count "origin/master..$branch")
if [ "$n" -ge 1 ] && [ "$n" -le "$max" ]; then note OK "$n commit(s) ahead of origin/master"
else note FAIL "$n commit(s) ahead of origin/master (want 1..$max)"; fail=1; fi

if git merge-base --is-ancestor origin/master "$branch"; then
  note OK "branch is based on current origin/master"
else
  note FAIL "branch is behind origin/master — run: git rebase origin/master"; fail=1
fi

if [ -z "$(git log --merges --format=%h "origin/master..$branch")" ]; then
  note OK "no merge commits"
else
  note FAIL "contains merge commits — rebase instead of merging"; fail=1
fi

missing=$(git log --format='%H' "origin/master..$branch" | while read -r sha; do
  git log -1 --format=%B "$sha" | grep -q '^Signed-off-by: ' || echo "$sha"
done)
if [ -z "$missing" ]; then note OK "every commit has a Signed-off-by (DCO)"
else note FAIL "commits without Signed-off-by: $missing"; fail=1; fi

# PII gate: fork-only delta must be clean before this branch is offered for review.
if bash "$HOME/.config/cartography-ops/pii-scan.sh" "upstream/master..$branch" >/tmp/cb-pii.$$ 2>&1; then
  note OK "PII scan clean"
else
  note FAIL "PII scan flagged content — see /tmp/cb-pii.$$"; fail=1
fi
rm -f /tmp/cb-pii.$$

printf '%s\n' "files touched:"
git diff --name-only "origin/master..$branch" | sed 's/^/  - /'
[ "$fail" -eq 0 ] && echo "RESULT: PASS" || echo "RESULT: FAIL"
exit "$fail"
