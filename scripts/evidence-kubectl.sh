#!/usr/bin/env bash
# Evidence collection — copy/paste each block, or run this file.
# Pod/namespace per your cluster: neo4j-0 in cloud-inventory.
set -uo pipefail

NS=cloud-inventory
POD=neo4j-0
CONTAINER=neo4j
USER=neo4j
PW="${NEO4J_PWD:?set NEO4J_PWD (or edit this line)}"

q() { kubectl -n "$NS" exec -i "$POD" -c "$CONTAINER" -- \
        cypher-shell -u "$USER" -p "$PW" --format plain; }

# ---------------------------------------------------------------- A1 (go/no-go)
# Expect > 0. If 0, the property never landed — don't open the PR.
q <<'CY'
MATCH (a:AWSAccount) WHERE a.account_password_present IS NOT NULL
RETURN count(a) AS accounts_with_property;
CY

# ------------------------------------------------------------ A2 (safe to paste)
q <<'CY'
MATCH (a:AWSAccount) WHERE a.account_password_present IS NOT NULL
RETURN a.account_password_present AS password_present, count(*) AS accounts
ORDER BY password_present;
CY

# ------------------------------------------------------ A3 (three counts equal?)
q <<'CY'
MATCH (a:AWSAccount) WHERE a.account_password_present IS NOT NULL
RETURN count(a) AS with_password_flag,
       count(a.account_mfa_enabled) AS with_mfa_flag,
       count(a.account_access_keys_present) AS with_keys_flag;
CY

# -------------------------------------------------------------------------- A4
q <<'CY'
MATCH (a:AWSAccount)
WHERE a.account_password_present = 0 AND a.account_mfa_enabled = 0
RETURN count(*) AS accounts_without_root_credentials;
CY

# -------------------------------------------------------------------------- B1
q <<'CY'
MATCH (a:AWSAccount) WHERE a.org_id IS NOT NULL
RETURN count(*) AS org_accounts, count(a.name) AS with_name;
CY

# ------------------------------------- B2 RAW NAMES — read yourself, don't paste
q <<'CY'
MATCH (a:AWSAccount) WHERE a.org_id IS NOT NULL
RETURN a.name AS name ORDER BY name;
CY

# ------------------------------------------------- B2 shape only (safe to paste)
q <<'CY'
MATCH (a:AWSAccount) WHERE a.org_id IS NOT NULL
RETURN count(*) AS org_accounts,
       count(CASE WHEN a.name STARTS WITH "scan-" THEN 1 END) AS looks_like_profile_name,
       count(CASE WHEN a.name IS NULL OR a.name = "" THEN 1 END) AS missing_name;
CY

# -------------------------------------------------------------------------- B3
q <<'CY'
MATCH (a:AWSAccount)
RETURN count(*) AS total_accounts, count(a.org_id) AS with_org_id;
CY

# ------------------------------------------------------------------- A5: logs
kubectl -n "$NS" logs job/"$(kubectl -n "$NS" get jobs --no-headers \
  | awk 'tolower($1) ~ /iam/ {print $1}' | tail -1)" \
  | grep -iE 'account summary|AWSAccountSummary|Syncing IAM' | head -20

# ------------------------------------------------------------------- B4: logs
kubectl -n "$NS" logs job/"$(kubectl -n "$NS" get jobs --no-headers \
  | awk 'tolower($1) ~ /organizations/ {print $1}' | tail -1)" \
  | grep -iE 'Loaded .* AWSAccount nodes|load_aws_accounts' | head -10
