# Backlog tracking

`tiagoasousa/cartography` has **issues disabled** (`has_issues=false`), so
per-branch tracking notes live here, next to the branch model they belong to.

| File | Branch | Upstream status | Action |
|---|---|---|---|
| `2026-11-26-iprange-shared-cleanup.md` | `fix/iprange-shared-cleanup-2928` | #2928 open, competing PR **#3705 open** | keep local, drop when #3705 merges |

## Why notes here instead of GitHub issues

- The fork cannot hold issues.
- These are fork-only branches; upstream would close a tracking issue for work
  it already has a PR for.
- The note must live somewhere durable and versioned — this branch.

## Rule for fork-only branches that have an upstream issue

If an upstream issue already exists and no PR implements it, open the PR
upstream (that is the goal). If an upstream **PR** already exists from someone
else, do not compete: keep the local branch, add a note here pointing at that
PR, and drop the branch when it merges.
