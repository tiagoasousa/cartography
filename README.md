# cartography fork ops

Branch model and tooling for `tiagoasousa/cartography`. Lives on an orphan
`ops` branch so it never touches the upstream mirror or a PR diff.

## The three refs

| ref | rule |
|---|---|
| `master` | strict 1:1 mirror of `cartography-cncf/cartography`. Fast-forward only. Never a local commit. |
| `feat/<name>`, `fix/<name>` | one logical change, branched from `master`, one upstream PR, one signed-off commit. |
| `franken-master` | rebuilt from `franken.manifest` by cherry-pick. The deployable artifact. Never hand-edited. |

`franken-master` is *rebuilt*, not merged, so it cannot accumulate merge commits
or stale integration branches. Its divergence from `master` is exactly the
manifest, auditable patch-by-patch.

## Scripts

| script | purpose |
|---|---|
| `scripts/mirror-master.sh` | ff master to upstream, push, refuse local commits |
| `scripts/new-change.sh` | branch + worktree + venv off `origin/master` |
| `scripts/check-branch.sh` | PR-readiness gate (commits, base, DCO, PII) |
| `scripts/rebuild-franken.sh` | rebuild franken-master from the manifest |
| `scripts/pr-status.sh` | open PRs, local branch state, franken status |

## The PII gate

Every push runs `.git/hooks/pre-push` in the main clone, which calls
`~/.config/cartography-ops/pii-scan.sh`. It blocks AWS account IDs that are not
canonical placeholders, non-safe email domains, AWS key IDs, GitHub/PyPI tokens,
private keys, and anything matching `~/.config/cartography-ops/pii-deny.txt`.

By default it scans commits **not already reachable from a tracked remote** —
i.e. exactly what the push would publish for the first time. `PII_SCAN_STRICT=1`
scans the full range verbatim instead.

The deny-list lives outside the repo on purpose: real account IDs must never be
committed to the very repo the gate protects.
