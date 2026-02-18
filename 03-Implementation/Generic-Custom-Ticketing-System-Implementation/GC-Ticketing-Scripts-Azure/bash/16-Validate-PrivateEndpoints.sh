#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 16-Validate-PrivateEndpoints.sh (Azure)
#
# Validates private endpoints and private DNS record sets.
#
# Manual verification (Azure Portal):
# - Private endpoints: confirm pe-<prefix>-blob and pe-<prefix>-kv exist and are Approved
# - Private DNS zones: confirm A records were created for the endpoints
# ------------------------------------------------------------

parse_args_prefix_location "$@"

require_cmd az

RG="$(rg_name "$PREFIX")"

log "Private endpoints:"
az network private-endpoint list -g "$RG" --query "[].{name:name,state:provisioningState,location:location}" -o table

for zone in privatelink.blob.core.windows.net privatelink.vaultcore.azure.net; do
  if az network private-dns zone show -g "$RG" -n "$zone" >/dev/null 2>&1; then
    log "DNS zone $zone A record sets:"
    az network private-dns record-set a list -g "$RG" -z "$zone" --query "[].{name:name,ttl:ttl,fqdn:fqdn}" -o table
  else
    warn "DNS zone not found: $zone"
  fi
done

