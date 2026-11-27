# #3726 — Redshift DNS evidence, and why the box stays unticked

Live graph, 2026-11-27.

| query | result |
|---|---|
| `AWSRedshiftCluster` nodes | 4 |
| with `endpoint_address` | 4 |
| DNS records matching an endpoint (R3) | 0 |
| `DNS_POINTS_TO` → Redshift edges (R4) | 0 |
| dot/case-insensitive match (N1) | 0 |

## The matcher is not the problem

`AWSDNSRecord.value` is normalized at ingestion; `endpoint_address` is raw. That
asymmetry could have hidden a working join behind a failing equality, so the
zero was not trustworthy alone. Measured:

- all 4 `endpoint_address` values are already lowercase
- none carry a trailing dot
- no DNS record contains even an endpoint's first label as a substring

Normalized comparison therefore matches the raw comparison's zero. The absence
is real: no Route53 record in this estate resolves to any Redshift cluster.

The 4 clusters are presumably reached by their AWS endpoint directly, or by
names held outside Route53. 374 `DNS_POINTS_TO` → CloudFront edges on the same
graph show the DNS linking machinery works; Redshift just has no records.

## Why the PR box stays unticked

A zero cannot distinguish "correct matcher, nothing to match" from "broken
matcher". We have evidence the matcher is correct (the N1 checks, plus the
integration test), but no positive production edge. Marking the box would claim
more than the data shows.

What would close it: a cluster reachable through a Route53 CNAME. The integration
test models that case; this estate does not happen to contain it.

## Process note

The first version of the normalization query used `trim(d.value, '.')`. In Cypher
that trims a character *set*, and it stripped the whole string, so every row
compared as `'.' = '.'` and returned 3 false matches on seeded data. Caught by
seeding known values and checking the count was 1, not 3. Use
`left(s, size(s) - 1)` for a trailing-dot strip.
