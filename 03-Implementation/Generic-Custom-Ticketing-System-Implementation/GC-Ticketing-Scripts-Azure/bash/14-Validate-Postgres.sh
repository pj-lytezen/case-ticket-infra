#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 14-Validate-Postgres.sh (Azure)
#
# Validates the Postgres Flexible Server and database.
#
# Manual verification (Azure Portal):
# - Postgres flexible server exists and public access is disabled
# - Private DNS zone exists and linked to vnet-<prefix>
# ------------------------------------------------------------

PREFIX="gc-tkt-prod"
LOCATION="eastus"
PG_NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix|-Prefix) PREFIX="$2"; shift 2;;
    --location|-Location) LOCATION="$2"; shift 2;;
    --postgres-name|--PostgresServerName) PG_NAME="$2"; shift 2;;
    *) die "Unknown argument: $1";;
  esac
done

require_cmd az

RG="$(rg_name "$PREFIX")"
SUFFIX="$(det_suffix)"
DEFAULT_PG="$(to_global_name "pg${PREFIX}${SUFFIX}" 63)"
PG="${PG_NAME:-$DEFAULT_PG}"

az postgres flexible-server show -g "$RG" -n "$PG" --query "{name:name,state:state,version:version,fqdn:fullyQualifiedDomainName}" -o jsonc
az postgres flexible-server db show -g "$RG" -s "$PG" -d gc_ticketing --query "{name:name}" -o jsonc

