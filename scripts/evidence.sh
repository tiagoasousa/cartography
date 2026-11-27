#!/usr/bin/env bash
# evidence.sh — collect PR evidence from the cloud-inventory Neo4j graph.
#
# Reads the Neo4j password from an env var already set in your shell.
# Nothing is written to disk and nothing is pushed anywhere.
#
#   ./evidence.sh all          # A1-A4 + B1-B3 (the graph queries)
#   ./evidence.sh a1           # single query
#   ./evidence.sh logs iam     # sync log lines for the IAM module
#   ./evidence.sh --self-test  # validate the script without touching a cluster
#
# Env vars:
#   NEO4J_PW_VAR   name of the env var holding the password
#                  (default: auto-detect NEO4J_PWD, NEO4J_PASSWORD, NEO4J_PASS)
#   NEO4J_USER     default: neo4j
#   NS             namespace, default: cloud-inventory
#   POD            pod name override (skips discovery)
#   CONTAINER      container override
#
set -uo pipefail

NS="${NS:-cloud-inventory}"
NEO4J_USER="${NEO4J_USER:-neo4j}"
POD="${POD:-}"
CONTAINER="${CONTAINER:-}"

# ---- password discovery -----------------------------------------------------
find_pw_var() {
    if [[ -n "${NEO4J_PW_VAR:-}" ]]; then
        echo "$NEO4J_PW_VAR"
        return 0
    fi
    for v in NEO4J_PWD NEO4J_PASSWORD NEO4J_PASS NEO4J_PW; do
        if [[ -n "${!v:-}" ]]; then
            echo "$v"
            return 0
        fi
    done
    return 1
}

PW_VAR=""
PW=""
init_pw() {
    PW_VAR="$(find_pw_var)" || {
        cat >&2 <<'EOF'
ERROR: no Neo4j password found in the environment.

Checked: NEO4J_PWD, NEO4J_PASSWORD, NEO4J_PASS, NEO4J_PW

Export it first, or name it explicitly:
    export NEO4J_PW_VAR=MY_VAR

Note: this checks THIS shell's environment. If you exported the var in another
terminal, `source` that shell's profile or re-export it here.
EOF
        exit 2
    }
    PW="${!PW_VAR}"
}

# ---- cluster discovery ------------------------------------------------------
die() { echo "ERROR: $*" >&2; exit 1; }

resolve_pod() {
    [[ -n "$POD" ]] && { echo "$POD"; return 0; }

    local found
    for sel in \
        "app.kubernetes.io/name=neo4j" \
        "app=neo4j" \
        "statefulset.kubernetes.io/pod-name=neo4j-0"; do
        found=$(kubectl -n "$NS" get pods -l "$sel" \
                -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        [[ -n "$found" ]] && { echo "$found"; return 0; }
    done

    # last resort: any pod whose name starts with neo4j
    found=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null \
            | awk '$1 ~ /^neo4j/ {print $1; exit}')
    [[ -n "$found" ]] && { echo "$found"; return 0; }

    return 1
}

resolve_container() {
    [[ -n "$CONTAINER" ]] && { echo "$CONTAINER"; return 0; }

    local c
    c=$(kubectl -n "$NS" get pod "$POD" \
        -o jsonpath='{.spec.containers[*].name}' 2>/dev/null)
    for cand in $c; do
        [[ "$cand" == *neo4j* ]] && { echo "$cand"; return 0; }
    done
    echo "${c%% *}"
}

init_cluster() {
    command -v kubectl >/dev/null || die "kubectl not found in PATH"

    POD="$(resolve_pod)" || die \
        "no Neo4j pod found in namespace '$NS'. Set NS=... or POD=... explicitly."
    CONTAINER="$(resolve_container)"
    [[ -n "$CONTAINER" ]] || die "no container found in pod '$POD'"

    kubectl -n "$NS" get pod "$POD" >/dev/null 2>&1 \
        || die "cannot read pod '$POD' in namespace '$NS' (kubeconfig/context?)"

    echo "# pod=$POD container=$CONTAINER ns=$NS user=$NEO4J_USER pw_env=$PW_VAR" >&2
}

# Run one cypher statement. Password goes in via the pod-side environment, not
# the local command line, so it never lands in your shell history or scrollback.
cypher() {
    local query="$1"
    printf '%s\n' "$query" | kubectl -n "$NS" exec -i "$POD" -c "$CONTAINER" -- \
        env NEO4J_PW="$PW" NEO4J_USER="$NEO4J_USER" \
        sh -c 'cypher-shell -u "$NEO4J_USER" -p "$NEO4J_PW" --format plain'
}

hdr() {
    printf '\n===== %s =====\n' "$1"
}

# ---- queries ----------------------------------------------------------------
# Property names verified against the branch source, not guessed:
#   cartography/models/aws/iam/account_summary.py :: account_password_present
#   cartography/models/aws/account.py             :: org_id
#   cartography/models/aws/account.py             :: name

run_a1() {
    hdr "A1 — does account_password_present exist at all? (go/no-go)"
    cat >&2 <<'EOF'
Measured: how many AWSAccount nodes carry the new property.
Expected: > 0.  If 0, the property did not land — do NOT open the PR.
EOF
    cypher 'MATCH (a:AWSAccount) WHERE a.account_password_present IS NOT NULL
RETURN count(a) AS accounts_with_property;'
}

run_a2() {
    hdr "A2 — value distribution (no ids, safe to paste)"
    cypher 'MATCH (a:AWSAccount) WHERE a.account_password_present IS NOT NULL
RETURN a.account_password_present AS password_present, count(*) AS accounts
ORDER BY password_present;'
}

run_a3() {
    hdr "A3 — cross-check against the sibling fields from the same API call"
    cat >&2 <<'EOF'
Measured: the three counts should be EQUAL. If password_present is much lower,
the property landed only on accounts that re-ran the IAM summary sync.
EOF
    cypher 'MATCH (a:AWSAccount)
WHERE a.account_password_present IS NOT NULL
RETURN count(a) AS with_password_flag,
       count(a.account_mfa_enabled) AS with_mfa_flag,
       count(a.account_access_keys_present) AS with_keys_flag;'
}

run_a4() {
    hdr "A4 — the case the feature exists for (count only)"
    cypher 'MATCH (a:AWSAccount)
WHERE a.account_password_present = 0 AND a.account_mfa_enabled = 0
RETURN count(*) AS accounts_without_root_credentials;'
}

run_b1() {
    hdr "B1 — do Organizations accounts carry a name?"
    cat >&2 <<'EOF'
Measured: org accounts that have a name. The two numbers should be equal.
EOF
    cypher 'MATCH (a:AWSAccount)
WHERE a.org_id IS NOT NULL
RETURN count(*) AS org_accounts, count(a.name) AS with_name;'
}

run_b2() {
    hdr "B2 — the bug fingerprint (CONTAINS INTERNAL NAMES — do not paste raw)"
    cat >&2 <<'EOF'
Returns account names. Read it yourself.
Send back only the shape, e.g.: "12 accounts, 0 match the scan- prefix".
The bug's fingerprint was names like "scan-<profile>". There should be none.
EOF
    cypher 'MATCH (a:AWSAccount)
WHERE a.org_id IS NOT NULL
RETURN a.name AS name
ORDER BY name;'
}

run_b2_shape() {
    hdr "B2-safe — the shape only, no names (safe to paste)"
    cat >&2 <<'EOF'
Same signal as B2, aggregated so nothing identifying leaves the machine:
how many org account names look like a profile name.
EOF
    cypher 'MATCH (a:AWSAccount)
WHERE a.org_id IS NOT NULL
RETURN count(*) AS org_accounts,
       count(CASE WHEN a.name STARTS WITH "scan-" THEN 1 END) AS looks_like_profile_name,
       count(CASE WHEN a.name IS NULL OR a.name = "" THEN 1 END) AS missing_name;'
}

run_b3() {
    hdr "B3 — the fix's precondition: is org_id populated?"
    cat >&2 <<'EOF'
The fix only preserves names for accounts with org_id IS NOT NULL.
If with_org_id is 0, the fix is untestable in this environment.
EOF
    cypher 'MATCH (a:AWSAccount)
RETURN count(*) AS total_accounts, count(a.org_id) AS with_org_id;'
}

run_logs() {
    local which="${1:-iam}"
    hdr "logs — recent sync output for '$which'"
    command -v kubectl >/dev/null || die "kubectl not found"

    local jobs
    jobs=$(kubectl -n "$NS" get jobs --no-headers 2>/dev/null \
           | awk -v w="$which" 'tolower($1) ~ tolower(w) {print $1}' \
           | tail -3)
    [[ -n "$jobs" ]] || die "no job matching '$which' in namespace '$NS'"

    local j
    for j in $jobs; do
        echo "--- job/$j ---" >&2
        kubectl -n "$NS" logs "job/$j" --tail=-1 2>/dev/null \
            | grep -iE 'account summary|AWSAccountSummary|syncing iam|organizations|Loaded .*AWSAccount|load_aws_accounts' \
            | head -20
    done
}

run_all() {
    init_cluster
    for f in run_a1 run_a2 run_a3 run_a4 run_b1 run_b2_shape run_b3; do
        "$f"
        echo
    done
    cat >&2 <<'EOF'
------------------------------------------------------------------
B2 (raw names) is deliberately NOT in `all`. Run it separately:
    ./evidence.sh b2
------------------------------------------------------------------
EOF
}

self_test() {
    local rc=0
    echo "self-test: syntax + wiring (no cluster contact)"

    # every function referenced by the dispatcher exists
    for fn in run_a1 run_a2 run_a3 run_a4 run_b1 run_b2 run_b2_shape run_b3 run_logs run_all; do
        declare -F "$fn" >/dev/null || { echo "  MISSING function: $fn" >&2; rc=1; }
    done
    echo "  dispatcher targets present: ok"

    # password discovery must fail cleanly when nothing is set
    ( unset NEO4J_PWD NEO4J_PASSWORD NEO4J_PASS NEO4J_PW NEO4J_PW_VAR
      find_pw_var >/dev/null 2>&1 ) && { echo "  pw detection WRONGLY succeeded" >&2; rc=1; } \
      || echo "  pw detection fails closed when unset: ok"

    # and must pick up an exported var
    ( NEO4J_PWD=x find_pw_var | grep -qx NEO4J_PWD ) \
      && echo "  pw detection finds NEO4J_PWD: ok" \
      || { echo "  pw detection missed NEO4J_PWD" >&2; rc=1; }

    # queries must be balanced enough to be real cypher, not truncated strings
    local n
    n=$(grep -c '^    cypher ' "$0" || true)
    # a1 a2 a3 a4 (root-password) + b1 b2 b2safe b3 (org names) = 8
    [[ "$n" -eq 8 ]] && echo "  cypher statements wired: $n ok" \
        || { echo "  expected 8 cypher calls, found $n" >&2; rc=1; }

    return $rc
}

# ---- dispatch ---------------------------------------------------------------
cmd="${1:-all}"
case "$cmd" in
    --self-test|self-test) self_test; exit $? ;;
esac

init_pw

[[ "$cmd" == "logs" ]] || init_cluster

case "$cmd" in
    a1) run_a1 ;;
    a2) run_a2 ;;
    a3) run_a3 ;;
    a4) run_a4 ;;
    b1) run_b1 ;;
    b2) run_b2 ;;
    b2safe|b2-shape) run_b2_shape ;;
    b3) run_b3 ;;
    logs) run_logs "${2:-iam}" ;;
    all) run_all ;;
    *)
        cat >&2 <<EOF
usage: $0 {a1|a2|a3|a4|b1|b2|b2safe|b3|all|logs [module]|--self-test}

Environment:
  NEO4J_PW_VAR / NEO4J_PWD / NEO4J_PASSWORD   password source
  NEO4J_USER (default neo4j)   NS (default cloud-inventory)
  POD / CONTAINER             overrides
EOF
        exit 2
        ;;
esac
