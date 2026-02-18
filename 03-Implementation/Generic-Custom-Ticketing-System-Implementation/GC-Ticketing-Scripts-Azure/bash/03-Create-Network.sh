#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 03-Create-Network.sh (Azure)
#
# Creates:
# - Resource group: rg-<prefix>
# - VNet: vnet-<prefix>
# - Subnets:
#   - snet-public
#   - snet-app
#   - snet-aks
#   - snet-data
#   - snet-pe (private endpoints)
#   - snet-pg (delegated to Postgres Flexible Server)
# - NAT Gateway + Standard Public IP
# - NAT association to private subnets (app/aks/data/pe)
#
# Design alignment:
# - “Private-by-default” posture: private subnets egress via NAT.
#
# Idempotency:
# - If RG/VNet/subnets/NAT already exist, script reuses them.
# ------------------------------------------------------------

PREFIX="gc-tkt-prod"
LOCATION="eastus"
VNET_CIDR="10.20.0.0/16"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix|-Prefix) PREFIX="$2"; shift 2;;
    --location|-Location) LOCATION="$2"; shift 2;;
    --vnet-cidr|--VpcCidr) VNET_CIDR="$2"; shift 2;;
    *) die "Unknown argument: $1";;
  esac
done

require_cmd az

RG="$(rg_name "$PREFIX")"
ensure_rg "$RG" "$LOCATION"

VNET="vnet-$PREFIX"

if az network vnet show -g "$RG" -n "$VNET" >/dev/null 2>&1; then
  log "VNet exists: $VNET"
else
  log "Creating VNet: $VNET ($VNET_CIDR)"
  az network vnet create -g "$RG" -n "$VNET" --address-prefixes "$VNET_CIDR" \
    --tags Project=SupportTicketAutomation Environment=prod Prefix="$PREFIX" >/dev/null
fi

ensure_subnet() {
  local name="$1" cidr="$2" delegation="${3:-}"
  if az network vnet subnet show -g "$RG" --vnet-name "$VNET" -n "$name" >/dev/null 2>&1; then
    log "Subnet exists: $name"
    return
  fi
  log "Creating subnet: $name ($cidr)"
  if [[ -n "$delegation" ]]; then
    az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n "$name" --address-prefixes "$cidr" \
      --delegations "$delegation" >/dev/null
  else
    az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n "$name" --address-prefixes "$cidr" >/dev/null
  fi
}

# Address plan (simple, predictable; adjust as needed).
ensure_subnet snet-public "10.20.0.0/24"
ensure_subnet snet-app    "10.20.10.0/24"
ensure_subnet snet-aks    "10.20.20.0/22"
ensure_subnet snet-data   "10.20.30.0/24"
ensure_subnet snet-pe     "10.20.50.0/24"
ensure_subnet snet-pg     "10.20.40.0/24" "Microsoft.DBforPostgreSQL/flexibleServers"

NAT="nat-$PREFIX"
PIP="pip-nat-$PREFIX"

if az network nat gateway show -g "$RG" -n "$NAT" >/dev/null 2>&1; then
  log "NAT Gateway exists: $NAT"
else
  if az network public-ip show -g "$RG" -n "$PIP" >/dev/null 2>&1; then
    log "Public IP exists: $PIP"
  else
    log "Creating Public IP for NAT: $PIP"
    az network public-ip create -g "$RG" -n "$PIP" --sku Standard --allocation-method Static \
      --tags Project=SupportTicketAutomation Prefix="$PREFIX" >/dev/null
  fi

  log "Creating NAT Gateway: $NAT"
  az network nat gateway create -g "$RG" -n "$NAT" --public-ip-addresses "$PIP" --idle-timeout 10 \
    --tags Project=SupportTicketAutomation Prefix="$PREFIX" >/dev/null
fi

# Associate NAT to private subnets that need outbound connectivity.
for snet in snet-app snet-aks snet-data snet-pe; do
  nat_id="$(az network vnet subnet show -g "$RG" --vnet-name "$VNET" -n "$snet" --query natGateway.id -o tsv | tr -d '\r')"
  if [[ -n "$nat_id" ]]; then
    log "NAT already associated to $snet"
    continue
  fi
  log "Associating NAT to subnet: $snet"
  az network vnet subnet update -g "$RG" --vnet-name "$VNET" -n "$snet" --nat-gateway "$NAT" >/dev/null
done

log "Network foundation complete."
log "Next: ./04-Validate-Network.sh"

