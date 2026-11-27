#!/usr/bin/env python3
"""Verify that franken-master is exactly master + franken.manifest.

Rebuilds the manifest onto a scratch branch and compares the resulting tree with
franken-master. Catches both a manifest entry that no longer applies and a
franken-master that was hand-edited or built from a stale manifest — the two ways
the deployable artifact silently stops matching its own definition.

Run from the fork checkout. Exits 0 with "RESULT: PASS", 1 on drift.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

MARKER_PASS = "RESULT: PASS"


def git(*args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", *args], capture_output=True, text=True, check=check)


def rev(ref: str) -> str:
    out = git("rev-parse", "--verify", "-q", ref, check=False)
    if out.returncode != 0:
        sys.exit(f"FAIL cannot resolve ref: {ref}")
    return out.stdout.strip()


def read_manifest(path: Path) -> list[tuple[str, str]]:
    entries: list[tuple[str, str]] = []
    for lineno, raw in enumerate(path.read_text().splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        sha = line.split()[0]
        entries.append((sha, raw))
    if not entries:
        sys.exit(f"FAIL manifest has no entries: {path}")
    return entries


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="origin/master", help="ref to rebuild onto")
    ap.add_argument("--branch", default="franken-master", help="ref to compare")
    ap.add_argument("--manifest", required=True)
    args = ap.parse_args()

    manifest = Path(args.manifest)
    if not manifest.is_file():
        sys.exit(f"FAIL no manifest at {manifest}")

    base = rev(args.base)
    deployed = rev(args.branch)
    entries = read_manifest(manifest)
    print(f"  base:     {base[:8]} ({args.base})")
    print(f"  deployed: {deployed[:8]} ({args.branch})")
    print(f"  manifest: {len(entries)} patches")

    # Every patch must resolve here. A commit kept alive only by a feature branch
    # vanishes once that branch is deleted and GitHub garbage-collects it, breaking
    # the rebuild long after the branch was pruned. franken-pins is the durable
    # anchor holding every manifest commit.
    unresolvable = [
        sha
        for sha, _ in entries
        if git("cat-file", "-e", f"{sha}^{{commit}}", check=False).returncode
    ]
    if unresolvable:
        print("\n  unreachable patch commits:", file=sys.stderr)
        for sha in unresolvable:
            print(f"    {sha}", file=sys.stderr)
        print(
            "\n  The branch holding these was probably deleted. Push them into the\n"
            "  franken-pins anchor (see franken.manifest) before they are collected.",
            file=sys.stderr,
        )
        return 1

    # Build in a scratch worktree so the caller's checkout is never disturbed.
    scratch = (
        Path(git("rev-parse", "--show-toplevel").stdout.strip())
        / ".git"
        / "franken-verify"
    )
    git("worktree", "remove", "--force", str(scratch), check=False)
    if scratch.exists():
        import shutil

        shutil.rmtree(scratch, ignore_errors=True)
    git("worktree", "add", "--quiet", "--detach", str(scratch), base)

    def sgit(*a: str, check: bool = True) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["git", *a], cwd=scratch, capture_output=True, text=True, check=check
        )

    try:
        for i, (sha, _raw) in enumerate(entries, 1):
            subject = git("log", "-1", "--format=%s", sha, check=False)
            if subject.returncode != 0:
                print(
                    f"FAIL [{i:02d}] {sha[:8]} is not a commit in this repository",
                    file=sys.stderr,
                )
                return 1
            label = subject.stdout.strip()
            r = sgit("cherry-pick", "-x", sha, check=False)
            if r.returncode != 0:
                print(
                    f"FAIL [{i:02d}] {sha[:8]} does not apply: {label}", file=sys.stderr
                )
                print(r.stderr.strip(), file=sys.stderr)
                sgit("cherry-pick", "--abort", check=False)
                return 1
            print(f"  [{i:02d}] {sha[:8]} {label[:64]}")
        built = sgit("rev-parse", "HEAD").stdout.strip()
    finally:
        git("worktree", "remove", "--force", str(scratch), check=False)

    print(f"  rebuilt:  {built[:8]}")

    # Compare trees rather than commit ids: the rebuild is reproducible in content but
    # not in committer metadata, so a differing tree is the real signal.
    tree_built = git("rev-parse", f"{built}^{{tree}}").stdout.strip()
    tree_deployed = git("rev-parse", f"{deployed}^{{tree}}").stdout.strip()
    if tree_built == tree_deployed:
        print(f"{MARKER_PASS} — {args.branch} reproduces the manifest exactly")
        return 0

    print(
        f"FAIL {args.branch} differs from a fresh rebuild of the manifest "
        f"(tree {tree_deployed[:8]} != {tree_built[:8]})",
        file=sys.stderr,
    )
    diff = git("diff", "--stat", built, deployed, check=False).stdout
    print(
        diff or "  (trees differ but no file diff — check submodule/exec bits)",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
