"""Assert the installed cartography build carries every fork capability this repo needs.

Runs inside the built scan image. Each check names a symbol the assistant's rules or
query packs read out of the graph, so a fork patch that regresses one fails the MR
instead of the next scan.

Behaviour checks come last and are the ones that matter: a property can be declared
and still not work, which is exactly how the CloudFront origin_domain_names
duplicate and the ELBv2 RegexValues gap both shipped.
"""

from __future__ import annotations

import importlib
import sys
from collections.abc import Callable

FAILED: list[str] = []


def _attr(module_path: str, symbol: str, attribute: str) -> Callable[[], bool]:
    def check() -> bool:
        module = importlib.import_module(module_path)
        return hasattr(getattr(module, symbol), attribute)

    return check


def _check(description: str, fn: Callable[[], bool]) -> None:
    try:
        ok = bool(fn())
    except Exception as exc:  # any failure means "capability missing"
        ok = False
        description = f"{description} ({exc.__class__.__name__}: {exc})"
    print(f"  {'ok  ' if ok else 'FAIL'} {description}")
    if not ok:
        FAILED.append(description)


def main() -> int:
    # Properties the rules read out of the graph.
    for prop in (
        "origin_endpoints",
        "origin_domain_names",
        "behavior_path_patterns",
        "behavior_path_regexes",
        "behavior_target_origin_ids",
        "default_target_origin_id",
        "origin_id_domain_pairs",
    ):
        _check(
            f"CloudFrontDistributionNodeProperties.{prop}",
            _attr(
                "cartography.models.aws.cloudfront.distribution",
                "CloudFrontDistributionNodeProperties",
                prop,
            ),
        )

    _check(
        "AWSLambdaNodeProperties.functionurl",
        _attr(
            "cartography.models.aws.lambda_function.lambda_function",
            "AWSLambdaNodeProperties",
            "functionurl",
        ),
    )

    for prop in (
        "rule_path_patterns",
        "rule_path_regexes",
        "rule_host_regexes",
        "rule_target_group_arns",
        "rule_priorities",
        "rule_is_default",
    ):
        _check(
            f"ELBV2ListenerSchema.properties.{prop}",
            _attr(
                "cartography.models.aws.ec2.loadbalancerv2", "ELBV2ListenerSchema", prop
            ),
        )

    # Relationship classes the DNS exposure rules traverse.
    for module_path, symbol in (
        (
            "cartography.models.aws.route53.dnsrecord",
            "AWSDNSRecordToCloudFrontDistributionRel",
        ),
        (
            "cartography.models.aws.route53.dnsrecord",
            "AWSDNSRecordToRedshiftClusterRel",
        ),
        (
            "cartography.models.aws.cloudfront.distribution",
            "CloudFrontDistributionToLoadBalancerV2Rel",
        ),
        (
            "cartography.models.aws.apigateway.apigatewayintegration",
            "APIGatewayIntegrationToLambdaRel",
        ),
        ("cartography.models.aws.wafv2", "AWSWebACLToAPIGatewayV2StageRel"),
    ):
        _check(f"{module_path}.{symbol}", _attr(module_path, symbol, "__name__"))

    # Behaviour, not just presence.
    def iprange_is_unscoped() -> bool:
        from cartography.models.aws.ec2.security_group_rules import IpRangeSchema

        return getattr(IpRangeSchema(), "sub_resource_relationship", None) is None

    def dualstack_normalizes() -> bool:
        from cartography.intel.aws.route53 import _normalize_record_target

        return (
            _normalize_record_target("dualstack.lb-1.eu-west-1.elb.amazonaws.com")
            == "lb-1.eu-west-1.elb.amazonaws.com"
            and _normalize_record_target("dualstack.example.com")
            == "dualstack.example.com"
        )

    def listener_rules_keep_regex() -> bool:
        # A regex-only rule must not collapse to the "match any" empty string, and
        # case folding must not rewrite the pattern source (\S is not \s).
        from cartography.intel.aws.ec2 import load_balancer_v2s

        rules = load_balancer_v2s._transform_listener_rules(
            {
                "Rules": [
                    {
                        "Priority": "1",
                        "Conditions": [
                            {
                                "Field": "host-header",
                                "HostHeaderConfig": {
                                    "RegexValues": [r"^API\.\S+\.COM$"]
                                },
                            }
                        ],
                        "Actions": [{"Type": "forward", "TargetGroupArn": "tgA"}],
                    }
                ]
            }
        )
        regex = rules["rule_host_regexes"][0]
        if regex in (None, "", "^(?:)$"):
            return False
        import re

        return bool(re.match(regex, "api.example.com")) and not re.match(
            regex, "api. .com"
        )

    _check("IpRangeSchema has no sub_resource_relationship", iprange_is_unscoped)
    _check("route53 dualstack CNAME normalization", dualstack_normalizes)
    _check(
        "ELBv2 listener rules preserve RegexValues verbatim", listener_rules_keep_regex
    )

    if FAILED:
        print(f"\n{len(FAILED)} check(s) failed", file=sys.stderr)
        return 1
    print("\nRESULT: PASS - this build carries every fork capability the rules need")
    return 0


if __name__ == "__main__":
    sys.exit(main())
