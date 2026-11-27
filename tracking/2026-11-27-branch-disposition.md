# Fork branch disposition — 2026-11-27

All 267 fork branches are either upstream branches (256), your own, or bot refs.
This records the 23 fork-only branches and where each stands, so "which of my
branches still need a PR" has a written answer instead of being re-derived.

Fork issues are disabled, so this lives here rather than as a fork-side issue.

## Open PRs — 12

| PR | branch | what |
|---|---|---|
| #3621 | `feat/aws-apigatewayv2-stages` | API Gateway v2 stages + WAFv2 associations |
| #3622 | `feat/aws-lambda-function-url-config` | Lambda function URL configs |
| #3636 | `fix/aws-lambda-retry-budget-override` | retry budget override |
| #3716 | `feat/route53-cloudfront-dns` | Route53 → CloudFront |
| #3717 | `feat/apigateway-lambda-integration` | REST integrations → Lambda |
| #3720 | `feat/aws-iam-root-password-presence` | root password presence |
| #3721 | `fix/aws-organizations-account-names` | keep Organizations account names |
| #3722 | `feat/route53-dualstack-cname-matching` | ordinary CNAMEs → dualstack ELB |
| #3723 | `feat/cloudfront-alb-origins` | CloudFront → load balancer origins |
| #3724 | `stack/cloudfront-routing` | cache behavior routing + origin endpoints |
| #3725 | `feat/aws-elbv2-listener-rules` | ELBv2 listener rules |
| #3726 | `feat/route53-redshift-dns` | Route53 → Redshift |

## No PR, and none needed — 11

| branch | why not |
|---|---|
| `franken-master` | the rebuilt deployable artifact; never a PR |
| `ops` | orphan branch holding this tooling; never a PR |
| `dependabot/docker/master/python-3.15.0-slim` | dependabot's, upstream opens its own PRs |
| `dependabot/uv/master/minor-and-patch-9533060db2` | dependabot's |
| `feat/inspector-vulnerability-node` | **already merged upstream as #3555** |
| `feat/inspector-ec2-finding-sets` | **already merged upstream as #3559** |
| `feat/aws-cloudfront-origin-endpoints` | content carried by #3724; tip `35887475` is the pre-rebase commit #3724 superseded |
| `secp-aws-perimeter-sync` | old 8-feature umbrella; every feature has its own PR |
| `integration/custom-0.145.0` | build snapshot; transports #3725 |
| `integration/dns-exposure-evidence` | evidence snapshot; transports #3717 |
| `fix/iprange-shared-cleanup-2928` | deliberately held: competing upstream **PR #3705** |

## The one that was genuinely missed

`feat/route53-redshift-dns` — no PR existed and nothing upstream covered it.
Opened as **#3726** on 2026-11-27. It had been sitting since 2026-11-24,
complete with tests and a passing gate.

## Lesson

Counting open PRs is not the same as auditing branches. Two fork-only feature
branches were never dispositioned because earlier passes enumerated branches
that *looked* like features and missed the ones that did not match the
`feat/*`/`fix/*` pattern used by the existing PR set. Enumerate with
`git ls-remote --heads origin` diffed against upstream, then classify every
row — do not sample.
