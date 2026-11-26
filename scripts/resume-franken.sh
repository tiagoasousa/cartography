#!/usr/bin/env bash
# Resume/continue a franken-master build: skip patches already applied (by
# patch-id), cherry-pick the rest. Safe to re-run after resolving a conflict.
set -uo pipefail
OPS="${CARTOGRAPHY_OPS:-$HOME/repos/cartography-ops}"
REPO="${CARTOGRAPHY_REPO:-$HOME/repos/cartography-work}"
MANIFEST="$OPS/franken.manifest"
cd "$REPO" || exit 2

git checkout --quiet franken-master || { echo "no franken-master branch" >&2; exit 1; }

applied=0; skipped=0; conflicted=0
while IFS= read -r line; do
  case "$line" in ''|'#'*) continue ;; esac
  sha=$(printf '%s' "$line" | awk '{print $1}')
  [ -z "$sha" ] && continue

  want=$(git show "$sha" | git patch-id --stable | cut -d' ' -f1)

  # already applied?
  found=0
  while IFS= read -r have; do
    [ -z "$have" ] && continue
    got=$(git show "$have" | git patch-id --stable | cut -d' ' -f1)
    [ "$got" = "$want" ] && { found=1; break; }
  done < <(git log --format=%H origin/master..HEAD)

  if [ "$found" -eq 1 ]; then skipped=$((skipped+1)); continue; fi

  if git cherry-pick -x "$sha" >/dev/null 2>&1; then
    applied=$((applied+1))
    printf '  applied %s\n' "${sha:0:8}"
  else
    # auto-resolve the known-benign case: "ours has it, theirs empty"
    files=$(git diff --name-only --diff-filter=U)
    ok=1
    for f in $files; do
      python3 - "$f" <<'PY' || ok=0
import re,sys
p=sys.argv[1]; s=open(p).read()
blocks=re.findall(r"<<<<<<< [^\n]*\n(.*?)=======\n(.*?)>>>>>>> [^\n]*\n", s, re.S)
if not blocks or not all(not t.strip() for o,t in blocks):
    sys.exit(1)
open(p,"w").write(re.sub(r"<<<<<<< [^\n]*\n(.*?)=======\n(.*?)>>>>>>> [^\n]*\n", lambda m:m.group(1), s, flags=re.S))
PY
    done
    if [ "$ok" -eq 1 ]; then
      git add $files
      git -c core.editor=true cherry-pick --continue >/dev/null 2>&1
      applied=$((applied+1)); printf '  resolved %s\n' "${sha:0:8}"
    else
      conflicted=1
      printf '  CONFLICT %s — resolve manually, then re-run\n' "${sha:0:8}" >&2
      git diff --name-only --diff-filter=U >&2
      break
    fi
  fi
done < "$MANIFEST"

echo "applied=$applied skipped=$skipped"
echo "franken-master: $(git rev-list --count origin/master..HEAD) commits on top of origin/master"
echo "head: $(git rev-parse --short HEAD)"
exit "$conflicted"
