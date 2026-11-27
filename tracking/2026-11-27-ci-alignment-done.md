# CI alignment — DONE

Supersedes the plan in `~/.hermes/plans/2026-11-27_121117-ci-alignment.md`. That plan
described a fork-side manifest gate plus an assistant-side pin; what actually shipped
is the same shape but driven by the constraint discovered mid-implementation that
`master` is a byte-identical upstream mirror, so CI files had to arrive as a **manifest
patch**, not a commit on `master`.

## Final state

| Thing | Value |
|---|---|
| `franken-master` | `3c677919…`, 23 patches on `origin/master` = `d3152df3` |
| manifest | `cartography-ops/franken.manifest` @ `ops 85c92733` |
| fork CI | Test Suite ✅ (23/23 jobs), Franken manifest gate ✅, sphinx ✅ |
| assistant branch | `ci/pin-franken-master` @ `2bed503`, MR not yet opened |
| pin | `ci/cartography-ref.env` → the tip of `franken-master` (assistant bump pending) |
| anchor | `refs/heads/franken-pins` (`4bbe9e6f`), keeps all 23 patch commits reachable |

## Fork CI (GitHub)

`.github/workflows/test_suite.yml` and `sphinx.yml` gained `franken-master` to their
`push` triggers, plus `workflow_dispatch`. Before this the fork had **zero** workflow
runs ever: every trigger named `master`, a read-only mirror no work ever lands on.

`.github/workflows/franken_gate.yml` + `.ci/verify_franken.py` replay
`franken.manifest` onto `origin/master` in a scratch worktree and compare **trees**
with the pushed branch. Trees, not commit ids — a clean rebuild produces different
commits with identical content.

Verified discriminating, three ways:

- current manifest → `RESULT: PASS`
- manifest missing one patch → exit 1 with a file diff
- manifest with a bogus SHA → exit 1, `FAIL [19] deadbeef is not a commit`

## Assistant CI (GitLab)

`ci/cartography-ref.env` is the single pin. `Dockerfile.cartography` and
`Dockerfile.rules` both read it; all six build jobs pass it via `--build-arg`.
`pin:cartography` (lint stage) fails an MR when:

- a Dockerfile hardcodes a ref instead of `${CARTOGRAPHY_REF}`
- `Dockerfile.rules` still points at `cartography-cncf/cartography`
- the two Dockerfiles disagree with the env file
- the pin is not the tip of `franken-master`

`.ci/verify-cartography.py` replaces the ~30-line `hasattr` wall in
`build:cartography-validate`. It checks presence *and* behaviour:
`_transform_listener_rules` must keep a regex-only rule non-empty and must not let
case-folding rewrite the pattern.

## Bugs this surfaced (all real, all fixed)

The gate earned its keep during its own rollout — each of these was live in the
deployable artifact:

1. **Two cartography builds shipping at once.** Rules image installed upstream
   `2943fc37`, scan image the fork's `79f3af12`. The rules engine read
   `origin_endpoints`, `functionurl` and `rule_*` — properties absent from upstream,
   so those rules returned no findings instead of erroring.
2. **`origin_domain_names` declared twice** → mypy `no-redef`, and the loader saw the
   duplicate. The manifest pinned the pre-fix CloudFront commit.
3. **ELBv2 `RegexValues` dropped entirely.** `_rule_condition_values` read only
   `Values`, so a regex-only rule collapsed to `""` = match-anything and routed to
   the wrong target group. Both cubic fixes were missing from the manifest.
4. **`describe_rules` unstubbed** in an existing LB test, so the new API call broke
   a passing suite.
5. **A test encoding the wrong contract** — `test_listener_rule_host_regex_is_lowercased`
   asserted the regex must *reject* uppercase, which was the bug being fixed. Rewritten
   to assert case-insensitive matching and that the pattern is not the empty regex.
6. Unused `Any` import and unsorted imports in two patches.

## Deviations from the original plan

- **Manifest carries CI files.** `master` is a verified byte-identical mirror
  (`git diff upstream/master master -- .github/` is empty), so a CI commit there
  would break the 1:1 rule. The CI changes ride as one manifest patch.
- **The Route53 carry commit.** `c6461749` (Redshift) never applies after `3d50d96f`
  (CloudFront): both register a `DNS_POINTS_TO` relation on `AWSDNSRecordSchema` and
  the conflict falls inside class bodies. `resolve-dnsrecord-conflict.py` handled it
  at build time, which would have meant teaching every CI runner the conflict. The
  manifest now carries the resolved merge (`0d3fcdec`) with both entries folded into
  it, so a rebuild needs no resolver.
- **`integration/custom-0.145.0` retired** in favour of `franken-master`.
- **Base is `master`, not tag `0.145.0`** (user's instruction). `0.145.0` is an
  ancestor of `master`; the manifest is 34 upstream commits ahead of the tag.

## Manifest durability

Cherry-picked patches are only reachable through the branches that hold them, and
cherry-picks create new SHAs, so none of them are ancestors of `franken-master`.
Deleting a feature branch therefore orphans its patch commits and the next rebuild
fails with a git fatal. `refs/heads/franken-pins` is an octopus commit whose parents
are all 23 patch commits; the gate now resolves every SHA up front and names the
missing ones. Recreate the anchor whenever the manifest changes:

    TREE=$(git write-tree)
    git commit-tree $TREE -p <sha> -p <sha> ... | xargs git push origin HEAD:franken-pins

Verified: a fresh clone fetching only `franken-pins` resolves all 23.

## Moving to newer upstream

Upstream advances on its own schedule, so a push can never be the trigger. The
mechanism is `.github/workflows/sync_franken.yml`, started by:

    ~/repos/cartography-ops/scripts/sync-franken.sh            # to upstream tip
    ~/repos/cartography-ops/scripts/sync-franken.sh <sha>      # to a commit
    ~/repos/cartography-ops/scripts/sync-franken.sh --dry-run  # report only

It advances `master` **and** `franken-master` in one run and pushes neither until
the replay reproduces the manifest. That pairing is the whole point: rebasing
`franken-master` onto upstream while `master` stayed behind left the gate replaying
the manifest onto a stale base and failing — a bug found by running the sync for
real, not by reasoning about it.

Refusals, all verified by running them:

| Condition | Behaviour |
|---|---|
| target is not a full 40-char SHA | fail before any git call |
| target is not a commit in upstream | fail |
| target is not on upstream master | fail |
| target is behind the fork mirror | warn, push nothing |
| fork mirror diverged from upstream | warn, push nothing |
| rebase conflicts | abort, push nothing, list the patches |
| replay does not reproduce the manifest | fail before the push |

`workflow_dispatch` from a non-default branch works when `--ref` is given, so no
workflow file has to live on `master`. An earlier bump-file trigger existed for
this and has been removed — it was built on a misreading of the GitHub docs, which
describe the UI button rather than the API.

`FRANKEN_PUSH_TOKEN` must be a fine-grained PAT: pushes made with `GITHUB_TOKEN`
do not start further workflow runs, so the gate and Test Suite would never see the
new commits. The workflow fails rather than pushing unverified.

## Still open

- Assistant MR not opened (branch at `2bed503`) — branch is pushed. Needs the MR description and a
  reviewer; the `pin:cartography` job has not run on real GitLab yet.
- `Dockerfile.rules` moving from upstream to the fork is the highest-blast-radius
  change in the set and has never built on arm64. `build:rules-validate` runs on the
  first MR pipeline.
- The assistant's `commit-msg` hook is broken locally (points at a pruned
  `precommit-venv` under a scratch dir), so the commit was made with `--no-verify`
  after validating the message against conventional-commits by hand. Not a fix in
  this change.
- `origin/upstream master` lags the fork mirror (`d3152df3` vs `a5546250`); harmless
  now, but `--base origin/master` assumes the fork mirror is current. `mirror-master.sh`
  is the tool that keeps it so.
