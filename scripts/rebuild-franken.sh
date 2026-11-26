#!/usr/bin/env bash
# Rebuild franken-master from scratch: cherry-pick every manifest patch onto
# current origin/master. Never merge, never hand-edit franken-master.
set -euo pipefail
OPS="${CARTOGRAPHY_OPS:-$HOME/repos/cartography-ops}"
REPO="${CARTOGRAPHY_REPO:-$HOME/repos/cartography-work}"
MANIFEST="$OPS/franken.manifest"
cd "$REPO"

git fetch --quiet upstream && git fetch --quiet origin
base=$(git rev-parse origin/master)
git branch -f franken-prev franken-master >/dev/null 2>&1 || true

if [ -n "$(git status --porcelain | grep -v '^??')" ]; then
  echo "REFUSING: working tree has uncommitted changes" >&2; exit 1
fi
git checkout --quiet -B franken-master "$base"

n=0; failed=0
while read -r sha owner subject; do
  case "${sha:-}" in ''|'#'*) continue ;; esac
  n=$((n+1))
  if git cherry-pick -x "$sha" >/dev/null 2>&1; then
    printf '  [%02d] %s %s\n' "$n" "${sha:0:8}" "$subject"
  else
    printf '  [%02d] %s CONFLICT  %s\n' "$n" "${sha:0:8}" "$subject" >&2
    echo "Resolve, then 'git cherry-pick --continue' and re-run." >&2
    failed=1; break
  fi
done < "$MANIFEST"

if [ "$failed" -eq 0 ]; then
  echo "franken-master: $n patches on ${base:0:8} -> $(git rev-parse --short HEAD)"
  echo "PII gate will run on push; to pre-check: ~/.config/cartography-ops/pii-scan.sh origin/master..franken-master"
  echo "push with: git push --force-with-lease origin franken-master"
else
  echo "rebase/conflict state left in place for manual resolution" >&2
fi
exit "$failed"
