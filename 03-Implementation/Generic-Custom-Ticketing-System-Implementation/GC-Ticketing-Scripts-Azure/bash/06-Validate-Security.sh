#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 06-Validate-Security.sh (Azure)
#
# Validates Key Vault and Log Analytics workspace.
#
# Manual verification (Azure Portal):
# - Key Vault -> Secrets: confirm pg-admin-user, pg-admin-password, app-config-json exist
# - Log Analytics workspace exists
# ------------------------------------------------------------

PREFIX="gc-tkt-prod"
LOCATION="eastus"
KEYVAULT_NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix|-Prefix) PREFIX="$2"; shift 2;;
    --location|-Location) LOCATION="$2"; shift 2;;
    --keyvault-name|--KeyVaultName) KEYVAULT_NAME="$2"; shift 2;;
    *) die "Unknown argument: $1";;
  esac
done

require_cmd az

RG="$(rg_name "$PREFIX")"
SUFFIX="$(det_suffix)"
DEFAULT_KV="$(to_global_name "kv${PREFIX}${SUFFIX}" 24)"
KV="${KEYVAULT_NAME:-$DEFAULT_KV}"
LAW="law-$PREFIX"

az keyvault show -g "$RG" -n "$KV" --query "{name:name,id:id}" -o jsonc
for s in pg-admin-user pg-admin-password app-config-json; do
  az keyvault secret show --vault-name "$KV" -n "$s" --query id -o tsv >/dev/null
  log "Secret OK: $s"
done

az monitor log-analytics workspace show -g "$RG" -n "$LAW" --query "{name:name,id:id}" -o jsonc

