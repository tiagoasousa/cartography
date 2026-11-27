#!/usr/bin/env python3
"""Resolve the Route53 DNS_POINTS_TO conflict that recurs when rebuilding
franken-master.

Several patches add a DNS_POINTS_TO relationship to AWSDNSRecordSchema. git
conflicts because they edit the same class list — and the conflict boundaries
fall inside class bodies, so "keep both sides" yields invalid Python. The
resolution is always the same four blocks, replaced here with exact literals:

  1. the two RelProperties classes, sharing one lastupdated line
  2. the two RelSchema classes (matcher differs: domain_name vs endpoint_address)
  3. each class's own `properties =` assignment
  4. both registrations in OtherRelationships

Plus the test file's import block. Verified by parsing the result.
"""
import subprocess
import sys
from pathlib import Path

REPO = Path(sys.argv[1] if len(sys.argv) > 1 else "/home/tiago/repos/cartography-work")
M = "<<<<<<< HEAD\n"
S = "=======\n"
E = ">>>>>>> c6461749 (Add Route53 DNS_POINTS_TO relationship for Redshift clusters)\n"

SPAN_START = "<<<<<<< HEAD\nclass AWSDNSRecordToCloudFrontDistributionRelProperties("
SPAN_END = (
    "AWSDNSRecordToRedshiftClusterRelProperties()\n"
    ">>>>>>> c6461749 (Add Route53 DNS_POINTS_TO relationship for Redshift clusters)\n"
    "    )\n"
)

SPAN_NEW = '''class AWSDNSRecordToCloudFrontDistributionRelProperties(CartographyRelProperties):
    lastupdated: PropertyRef = PropertyRef("lastupdated", set_in_kwargs=True)


@dataclass(frozen=True)
class AWSDNSRecordToRedshiftClusterRelProperties(CartographyRelProperties):
    lastupdated: PropertyRef = PropertyRef("lastupdated", set_in_kwargs=True)


@dataclass(frozen=True)
class AWSDNSRecordToCloudFrontDistributionRel(CartographyRelSchema):
    target_node_label: str = "AWSCloudFrontDistribution"
    target_node_matcher: TargetNodeMatcher = make_target_node_matcher(
        {
            "domain_name": PropertyRef("value"),
        }
    )
    direction: LinkDirection = LinkDirection.OUTWARD
    rel_label: str = "DNS_POINTS_TO"
    properties: AWSDNSRecordToCloudFrontDistributionRelProperties = (
        AWSDNSRecordToCloudFrontDistributionRelProperties()
    )


@dataclass(frozen=True)
class AWSDNSRecordToRedshiftClusterRel(CartographyRelSchema):
    target_node_label: str = "AWSRedshiftCluster"
    target_node_matcher: TargetNodeMatcher = make_target_node_matcher(
        {
            "endpoint_address": PropertyRef("value"),
        }
    )
    direction: LinkDirection = LinkDirection.OUTWARD
    rel_label: str = "DNS_POINTS_TO"
    properties: AWSDNSRecordToRedshiftClusterRelProperties = (
        AWSDNSRecordToRedshiftClusterRelProperties()
    )
'''


def resolve_span(src: str) -> tuple[str, bool]:
    """Blocks 1-3 interleave shared trunk lines, so replace them as one span."""
    i = src.find(SPAN_START)
    if i < 0:
        return src, False
    j = src.find(SPAN_END, i)
    if j < 0:
        return src, False
    j += len(SPAN_END)
    return src[:i] + SPAN_NEW + src[j:], True


BLOCK_LIST_OLD = f"""{M}            AWSDNSRecordToCloudFrontDistributionRel(),
{S}            AWSDNSRecordToRedshiftClusterRel(),
{E}"""
BLOCK_LIST_NEW = """            AWSDNSRecordToCloudFrontDistributionRel(),
            AWSDNSRecordToRedshiftClusterRel(),
"""

TEST_IMPORT_OLD = f"""{M}import cartography.intel.aws.cloudfront
{S}import copy

import cartography.intel.aws.redshift
{E}"""
TEST_IMPORT_NEW = """import copy

import cartography.intel.aws.cloudfront
import cartography.intel.aws.redshift
"""


def apply(path: Path, old: str, new: str) -> bool:
    src = path.read_text()
    if old not in src:
        return False
    path.write_text(src.replace(old, new, 1))
    return True


def main():
    out = subprocess.run(
        ["git", "-C", str(REPO), "diff", "--name-only", "--diff-filter=U"],
        capture_output=True, text=True,
    )
    files = [f for f in out.stdout.split() if f]
    if not files:
        print("nothing to resolve")
        return 1

    for f in files:
        p = REPO / f
        if f.endswith("test_route53.py"):
            ok = apply(p, TEST_IMPORT_OLD, TEST_IMPORT_NEW)
            print(f"  {f}: import block {'resolved' if ok else 'MISS'}")
        else:
            text, span_ok = resolve_span(p.read_text())
            p.write_text(text)
            r4 = apply(p, BLOCK_LIST_OLD, BLOCK_LIST_NEW)
            print(f"  {f}: span={span_ok} list={r4}")
        text = p.read_text()
        if "<<<<<<<" in text or ">>>>>>>" in text:
            print(f"  !! {f} still has markers", file=sys.stderr)
            return 1
        try:
            compile(text, str(p), "exec")
        except SyntaxError as e:
            print(f"  !! {f} does not parse: {e}", file=sys.stderr)
            return 1

    subprocess.run(["git", "-C", str(REPO), "add"] + files, check=True)
    print("resolved, parsed and staged")
    return 0


sys.exit(main())
