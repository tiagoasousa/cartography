# cubic-dev-ai review triage — 2026-11-27

20 inline comments across 10 PRs. Every one answered in-thread; 13 fixed in code,
7 declined or deferred with reasons. #3636 and #3720 came back clean (5/5).

## Fixed

| PR | comment | change | commit |
|---|---|---|---|
| #3622 | fail-open on URL fetch | non-not-found `ClientError` now aborts the region instead of returning `None`, which was writing `None` over a known URL | `85975338` |
| #3721 | null org name blanks account | query excludes `a.name IS NULL` so `dict.get` fallback applies | `f0f48d93` |
| #3723 | case path never exercised | fixture origin `DomainName` uppercased; removing `.lower()` now fails 2 tests | `96a4525e` |
| #3724 | `origin_endpoints` never declared | property added to the node schema — the loader had been dropping it entirely | `0a758a68` |
| #3724 | duplicate `origin_domain_names` | duplicate removed | `0a758a68` |
| #3724 | no `origin_endpoints` assertion | added, using the fixture's `/backup` OriginPath | `0a758a68` |
| #3724 | only 3 of 6 routing props asserted | all six asserted; dropping any one from the schema now fails | `9f92c276` |
| #3725 | `RegexValues` dropped (P1) | regex-only rule collapsed to `''` = "match any", selecting the wrong target group | `44817c92` |
| #3725 | `.lower()` corrupts regex source | `\S` became `\s`; replaced with inline `(?i:...)` group | `e042388e` |
| #3722 | isort order | isort did fail; import reordered | `2d56432e` |
| #3726 | no negative fixture | near-miss CNAME added + asserts zero edges | `276e19f8` |
| #3716 | no negative fixture | mixed-case fixture addressed in #3723; dedicated CF negative fixture still open | `96a4525e` |

Each fix was mutation-checked: the code was reverted and the test confirmed to
fail. Two of those checks changed what shipped —

- #3724's first integration test passed **with the feature removed** because it
  asserted `is None`, which is also true when the property was never set.
- #3725's first regex fix lowercased the pattern, which fixes `API` but turns
  `\S` into `\s`.

## Declined / deferred

| PR | comment | why |
|---|---|---|
| #3716 | add `cloudfront` to route53 deps | does not fix it: `route53` (position 130) runs before `cloudfront` (140), so the dependency list only warns. Real fix is reordering the sync or a post-pass — a fleet-wide change, not appropriate inside this PR. |
| #3726 | add `redshift` to route53 deps | not needed: `redshift` (123) already runs before `route53` (130). |
| #3722 | Network/Gateway LB `.elb.<region>` form | premise is wrong — ELB DNS is `<name>-<id>.<region>.elb.amazonaws.com`, which already ends with `.elb.amazonaws.com`. |
| #3717 | ARN regex too loose | valid; needs matching the exact integration URI form, and I want to confirm both legacy `lambda:path` and direct-ARN forms match first. |
| #3621 ×3 | stale (P1 GetStages, pagination, partition) | already fixed by `875eee8c`; answered with the current code. |
| #3621 ×2 | test strength | left as-is; the unit test asserts wiring, the integration test covers node shape. |

## Still open

- #3716: dedicated non-matching CloudFront fixture (the Redshift equivalent is done).
- #3717: tighten the ARN regex.
- #3621: assert both cleanup jobs actually run.
