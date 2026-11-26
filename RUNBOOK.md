# Runbook

## Start a change
```
mirror-master.sh          # never skip: branches must be based on today's master
new-change.sh feat <name> # or: new-change.sh fix <name>
# one commit: git commit -s -m "feat(aws): <what>"
```

## Before opening a PR
```
check-branch.sh feat/<name>          # must print RESULT: PASS
uv run pre-commit run --files $(git diff --name-only origin/master HEAD)
PYTHONPATH=$PWD .venv/bin/python -m pytest tests/unit -q
```

`check-branch.sh` includes the PII scan, so a PASS means no PII in the delta.

## Open the PR
```
gh pr create --repo cartography-cncf/cartography --base master \
  --head tiagoasousa:feat/<name> --title "<commit subject>" \
  --body-file /tmp/pr-body.md --draft
# then read the body back:
gh api repos/cartography-cncf/cartography/pulls/<n> --jq .body | head -20
```

## After the PR merges upstream
```
mirror-master.sh                       # brings it into master
# delete the branch (local + remote) and remove its line from franken.manifest
rebuild-franken.sh && git push --force-with-lease origin franken-master
```

## Deploy a new franken-master
```
sha=$(git rev-parse franken-master)    # in ~/repos/cartography-work
# bump ARG CARTOGRAPHY_REF in cartography-assistant/Dockerfile.cartography
# MR it; CI builds the image; verify inside the image:
#   python -c "import cartography.intel.aws.<module> as m, inspect; print(<marker> in inspect.getsource(m))"
```

## The PII gate

Runs on every push via `.git/hooks/pre-push`. To check by hand:
```
~/.config/cartography-ops/pii-scan.sh upstream/master..<branch>
```
Exit 0 = clean, 1 = BLOCKED, 2 = bad range.

It scans commits **not already published on a tracked remote** (new exposure).
`PII_SCAN_STRICT=1` scans the full range verbatim instead.

`~/.config/cartography-ops/pii-deny.txt` holds project-specific patterns (real
account IDs, internal domains). It lives outside the repo so the gate never
commits the very values it protects.

If the gate blocks: do not push. Strip the content, or if it is a genuine false
positive, tighten the classifier and re-review the diff by eye.

## Weekly hygiene
```
pr-status.sh                  # open PRs, local branches, franken status
git worktree list             # remove stale: git worktree remove <path>
```

## Failure modes seen in practice

- **A patch will not cherry-pick alone.** Some features depend on an earlier
  one (CF behavior routing needs `origin_domain_names`). Put both in one
  branch (`stack/<name>`) and keep them adjacent in the manifest.
- **`git checkout -B <branch>` fails** if another worktree holds that branch.
  Rebuild it from inside that worktree.
- **A stale `.venv`** (e.g. `pydantic_core` ImportError) is environment rot,
  not your code. Rebuild the venv before blaming a patch.
- **`tests/unit/cartography/intel/kubernetes/test_pods.py` and two kubernetes
  tests fail on current upstream master** — pre-existing, unrelated. Confirm
  by running them on `origin/master` before investigating.
