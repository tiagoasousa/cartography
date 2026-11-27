#!/usr/bin/env bash
# Evidence for PR #5 (cloudfront-alb-origins) and #6 (route53-dualstack-cname-matching)
# Blocks C1..C5 = CloudFront custom origins / SERVES_FROM
# Blocks D1..D5 = dualstack CNAME matching
# Copy/paste block by block, or run this file.
set -uo pipefail

NS=cloud-inventory
POD=neo4j-0
CONTAINER=neo4j
USER=neo4j
PW="${NEO4J_PWD:?set NEO4J_PWD (or edit this line)}"

q() { kubectl -n "$NS" exec -i "$POD" -c "$CONTAINER" -- \
        cypher-shell -u "$USER" -p "$PW" --format plain; }

# ===========================================================================
# Part C — feat/cloudfront-alb-origins
# Adds: AWSCloudFrontDistribution.origin_domain_names
#       (AWSCloudFrontDistribution)-[:SERVES_FROM]->(AWSLoadBalancerV2)
# ===========================================================================

# C1 — did the property land? (go/no-go: expect > 0)
# Compare against total distributions to see propagation.
q <<'CY'
MATCH (d:AWSCloudFrontDistribution)
RETURN count(d) AS total_distributions,
       count(d.origin_domain_names) AS with_origin_domain_names;
CY

# C2 — THE key query. Does the SERVES_FROM edge exist at all?
# Expect > 0 for a usable PR. If 0, this is a draft-or-drop decision.
q <<'CY'
MATCH (:AWSCloudFrontDistribution)-[r:SERVES_FROM]->(:AWSLoadBalancerV2)
RETURN count(r) AS serves_from_edges;
CY

# C3 — if C2 was 0: do LB origins EXIST that should have matched?
# Counts distributions whose origin_domain_names contains an ELB hostname.
# If this > 0 while C2 = 0, the gap is a missing LB node, not a code bug.
q <<'CY'
MATCH (d:AWSCloudFrontDistribution)
WHERE any(n IN d.origin_domain_names WHERE n CONTAINS '.elb.amazonaws.com'
                                     OR n CONTAINS '.elb.')
RETURN count(d) AS distributions_with_elb_origin;
CY

# C4 — root cause of the 0: are those ELB DNS names present as LB nodes?
# Compares the ELB hostnames referenced as origins against AWSLoadBalancerV2.dnsname.
q <<'CY'
MATCH (d:AWSCloudFrontDistribution)
WHERE any(n IN d.origin_domain_names WHERE n CONTAINS '.elb.')
WITH d, [n IN d.origin_domain_names WHERE n CONTAINS '.elb.'] AS elb_origins
UNWIND elb_origins AS origin
OPTIONAL MATCH (lb:AWSLoadBalancerV2 {dnsname: origin})
RETURN count(origin) AS elb_origin_refs,
       count(lb) AS matched_lb_nodes;
CY

# C5 — context: how many LB nodes exist at all in the graph?
q <<'CY'
MATCH (lb:AWSLoadBalancerV2)
RETURN count(lb) AS total_loadbalancer_v2_nodes;
CY

# ===========================================================================
# Part D — feat/route53-dualstack-cname-matching
# Makes ordinary CNAMEs to *.elb.amazonaws.com strip the dualstack. prefix,
# so they match AWSLoadBalancerV2.dnsname the way alias targets already do.
# ===========================================================================

# D1 — the bug fingerprint. Records targeting an ELB hostname, split by type,
# and how many STILL carry the dualstack. prefix (i.e. unfixed).
# Post-fix: still_has_dualstack_prefix should trend to 0.
q <<'CY'
MATCH (d:AWSDNSRecord)
WHERE d.value ENDS WITH 'elb.amazonaws.com'
RETURN d.type AS record_type,
       count(*) AS records,
       count(CASE WHEN d.value STARTS WITH 'dualstack.' THEN 1 END) AS still_has_dualstack_prefix
ORDER BY record_type;
CY

# D2 — the payoff: are ELB-targeted records actually linked to LB nodes?
# linked should equal total once every account has rescanned with the fix.
q <<'CY'
MATCH (d:AWSDNSRecord)
WHERE d.value ENDS WITH 'elb.amazonaws.com'
RETURN count(*) AS elb_targeted_records,
       count(CASE WHEN (d)-[:DNS_POINTS_TO]->(:AWSLoadBalancerV2) THEN 1 END) AS linked_to_lb;
CY

# D3 — the specific case this PR fixes: ordinary CNAMEs (not ALIAS) that
# were previously left with the prefix and therefore dead-ended.
q <<'CY'
MATCH (d:AWSDNSRecord {type: 'CNAME'})
WHERE d.value ENDS WITH 'elb.amazonaws.com'
RETURN count(*) AS cname_to_elb,
       count(CASE WHEN (d)-[:DNS_POINTS_TO]->(:AWSLoadBalancerV2) THEN 1 END) AS cname_linked;
CY

# D4 — residue: any ELB-targeted record still unmatched? (expect 0 post-fix)
# Lists the shape only, no hostnames.
q <<'CY'
MATCH (d:AWSDNSRecord)
WHERE d.value ENDS WITH 'elb.amazonaws.com'
  AND NOT (d)-[:DNS_POINTS_TO]->(:AWSLoadBalancerV2)
RETURN count(*) AS unmatched_elb_records,
       count(CASE WHEN d.value STARTS WITH 'dualstack.' THEN 1 END) AS of_which_unfixed;
CY

# D5 — totality check: all DNS_POINTS_TO edges into LBs, by source record type.
q <<'CY'
MATCH (d:AWSDNSRecord)-[:DNS_POINTS_TO]->(:AWSLoadBalancerV2)
RETURN d.type AS source_record_type, count(*) AS edges
ORDER BY edges DESC;
CY

# -------------------------------------------------------------------- logs
# C/D log evidence: cloudfront + route53 module output from the latest jobs
for mod in cloudfront route53; do
  echo "--- $mod ---" >&2
  kubectl -n "$NS" logs job/"$(kubectl -n "$NS" get jobs --no-headers 2>/dev/null \
    | awk -v m="$mod" 'tolower($1) ~ m {print $1}' | tail -1)" 2>/dev/null \
    | grep -iE "cloudfront|route53|origin|loaded .*dns" | head -10
done
