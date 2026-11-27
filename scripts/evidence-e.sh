#!/usr/bin/env bash
# Identify the CloudFront distribution whose origin load balancer is not in the graph.
# E1..E5. Same q() helper as the other evidence scripts.
set -uo pipefail

NS=cloud-inventory
POD=neo4j-0
CONTAINER=neo4j
USER=neo4j
PW="${NEO4J_PWD:?set NEO4J_PWD (or edit this line)}"

q() { kubectl -n "$NS" exec -i "$POD" -c "$CONTAINER" -- \
        cypher-shell -u "$USER" -p "$PW" --format plain; }

# E1 — WHICH distribution AND WHICH account. This is the answer to "which one"
# plus the account it belongs to. OPTIONAL MATCH so a distribution with no
# RESOURCE edge still returns (account columns NULL) instead of vanishing.
q <<'CY'
MATCH (d:AWSCloudFrontDistribution)
WHERE any(n IN d.origin_domain_names WHERE n CONTAINS 'lbw-web-production-1000965676')
OPTIONAL MATCH (owner:AWSAccount)-[:RESOURCE]->(d)
RETURN d.distribution_id  AS distribution_id,
       d.domain_name      AS domain_name,
       d.aliases          AS aliases,
       d.comment          AS comment,
       owner.name         AS account_name,
       owner.id           AS account_id,
       owner.inscope      AS account_inscope,
       d.lastupdated      AS distribution_lastupdated,
       owner.lastupdated  AS account_lastupdated;
CY

# E2 — WHICH account owns it, and when that account was last scanned.
# If account_lastupdated is much older than the distribution, the account
# is not being rescanned and the LB may simply be stale/absent from an old sync.
q <<'CY'
MATCH (a:AWSAccount)-[:RESOURCE]->(d:AWSCloudFrontDistribution)
WHERE any(n IN d.origin_domain_names WHERE n CONTAINS 'lbw-web-production-1000965676')
RETURN a.name AS account_name, a.id AS account_id,
       a.lastupdated AS account_lastupdated,
       d.distribution_id AS distribution_id;
CY

# E3 — KEY QUERY. Does the load balancer exist at all, under any spelling?
# Searches both LB labels by name substring, ignoring the zone suffix, and
# returns the OWNING ACCOUNT of any near-miss so you can see whether the LB
# lives in a different account than the distribution (cross-account origin).
# If this returns a row with a matching dnsname, the LB IS in the graph and the
# mismatch is the hostname form — not a collection gap.
q <<'CY'
MATCH (lb)
WHERE (lb:AWSLoadBalancerV2 OR lb:AWSLoadBalancer)
  AND (lb.name CONTAINS 'lbw-web-production'
       OR lb.dnsname CONTAINS 'lbw-web-production')
OPTIONAL MATCH (owner:AWSAccount)-[:RESOURCE]->(lb)
RETURN labels(lb)      AS node_labels,
       lb.name         AS lb_name,
       lb.dnsname      AS lb_dnsname,
       lb.region       AS region,
       lb.type         AS lb_type,
       owner.name      AS lb_account_name,
       owner.id        AS lb_account_id;
CY

# E4 — what does DNS say? Any record pointing at that hostname, or at the
# distribution, gives the intended traffic path and often names the service.
q <<'CY'
MATCH (r:AWSDNSRecord)
WHERE r.value CONTAINS 'lbw-web-production-1000965676'
   OR r.value CONTAINS 'lbw-web-production'
RETURN r.name AS record_name, r.type AS type, r.value AS value,
       r.zoneid AS zone_id;
CY

# E5 — did that account's ELB sync run at all? Compares the account's LB nodes
# against the whole graph. If this account has 0 LB nodes while others have many,
# the elbv2 module is failing or out of the scan's requested syncs for it.
q <<'CY'
MATCH (a:AWSAccount)-[:RESOURCE]->(d:AWSCloudFrontDistribution)
WHERE any(n IN d.origin_domain_names WHERE n CONTAINS 'lbw-web-production-1000965676')
OPTIONAL MATCH (a)-[:RESOURCE]->(v2:AWSLoadBalancerV2)
OPTIONAL MATCH (a)-[:RESOURCE]->(c1:AWSLoadBalancer)
RETURN a.name AS account_name,
       count(DISTINCT v2) AS lbv2_nodes_in_account,
       count(DISTINCT c1) AS classic_lb_nodes_in_account;
CY
