#!/usr/bin/env bash
# Open PRs + local change branches vs the mirror master.
set -uo pipefail
REPO="${CARTOGRAPHY_REPO:-$HOME/repos/cartography-work}"
UPSTREAM="cartography-cncf/cartography"
cd "$REPO" || exit 2
git fetch --quiet upstream origin

ME=$(gh api user --jq .login 2>/dev/null || echo unknown)
echo "=== upstream PRs by $ME ==="
nums=$(gh api "search/issues?q=repo:$UPSTREAM+author:$ME+type:pr+state:open&per_page=50" --jq '.items[].number' 2>/dev/null)
if [ -z "$nums" ]; then echo "  (none)"; fi
for n in $nums; do
  gh api "repos/$UPSTREAM/pulls/$n" \
    --jq '"  #\(.number) [\(.head.ref)] mergeable=\(.mergeable) state=\(.mergeStateStatus) review=\(.reviewDecision // "none")  \(.title)"' 2>/dev/null
done

echo
echo "=== local feat/fix branches vs origin/master ==="
for b in $(git for-each-ref --format='%(refname:short)' refs/heads | grep -E '^(feat|fix)/'); do
  ahead=$(git rev-list --count "origin/master..$b")
  remote=$(git ls-remote --heads origin "refs/heads/$b" 2>/dev/null | cut -c1-8)
  printf '  %-40s ahead=%-3s remote=%s\n' "$b" "$ahead" "${remote:-NOT-PUSHED}"
done

echo
echo "=== franken-master ==="
if git rev-parse --verify -q franken-master >/dev/null; then
  echo "  local : $(git rev-parse --short franken-master)  ($(git rev-list --count origin/master..franken-master) patches on origin/master)"
  echo "  remote: $(git ls-remote --heads origin refs/heads/franken-master 2>/dev/null | cut -c1-8 || echo absent)"
else
  echo "  (not built yet — run rebuild-franken.sh)"
fi
