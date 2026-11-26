## AWSIpRange gets a RESOURCE edge to every account that references the same CIDR

Tracking issue for a fork-carried fix. Upstream bug is **cartography-cncf/cartography#2928**; an open upstream PR from another contributor, **#3705**, proposes a fix.

We need this behaviour in our own build now, so we carry it as a local branch (`fix/iprange-shared-cleanup-2928`) rather than competing with #3705 upstream. This issue exists so the local branch has a tracked reason and a place to note when it can be dropped.

### Expected behavior

`AWSIpRange` is keyed on the CIDR string alone (`id` = e.g. `10.0.0.0/8`), so a single node is shared by every account that references that CIDR. Ownership should not be inferred from that sharing:

- An account that merely *references* a CIDR in a security group rule should not appear as the CIDR's owner.
- A scoped cleanup for one account must not delete a node that another account still references.

### Actual behavior

Every account that references the CIDR draws `(:AWSAccount)-[:RESOURCE]->(:AWSIpRange)`, which reads as multi-account ownership. Because the shared node is a sub-resource of each referencing account, one account's scoped cleanup `DETACH DELETE`s it — silently removing the node and its edges for the other accounts too. All affected rules then lose data until the next full sync of every referencing account.

### To Reproduce

1. Two accounts, A and B, each with a security group rule allowing the same CIDR, e.g. `10.215.0.0/16`.
2. Sync both accounts. Observe one `AWSIpRange` node with two incoming `RESOURCE` edges.
3. Remove A's rule, and re-sync **only A**.
4. Observe the `AWSIpRange` node is gone, even though B still references it.

### Logs

Not a crash — no stack trace. The evidence is graph state: `MATCH (a:AWSAccount)-[:RESOURCE]->(r:AWSIpRange {id: "10.215.0.0/16"}) RETURN a.id` returns both accounts after step 2 and no node at all after step 4.

### Please complete the following information

- Cartography: fork build on top of `master` (`a5546250`), carrying the local branch named above
- Python: 3.13
- OS: Linux

### Additional context

Our branch scopes the ownership/cleanup so one account can no longer claim or delete a shared `AWSIpRange` node, and adds integration tests for the two-account repro above.

Upstream status to watch:

- **#2928** — the open issue describing this bug.
- **#3705** — open PR from another contributor (`rafaelmv`), same root cause and essentially the same repro. It classifies the change as **breaking**, which ours currently does not.

When #3705 (or an equivalent) merges upstream, drop the local branch and take the upstream fix via `master`. Do not open a competing upstream PR while #3705 is open.
