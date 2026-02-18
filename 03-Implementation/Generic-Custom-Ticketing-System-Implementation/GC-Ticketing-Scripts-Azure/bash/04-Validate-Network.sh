#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 04-Validate-Network.sh (Azure)
#
# Validates the network created in 03-Create-Network.sh.
#
# Manual verification (Azure Portal):
# - Resource group rg-<prefix> exists and contains vnet-<prefix>, nat-<prefix>, pip-nat-<prefix>
# - VNet -> Subnets: confirm NAT gateway is associated to private subnets
# ------------------------------------------------------------

parse_args_prefix_location "$@"

require_cmd az

RG="$(rg_name "$PREFIX")"
VNET="vnet-$PREFIX"
NAT="nat-$PREFIX"

log "VNet:"
az network vnet show -g "$RG" -n "$VNET" --query "{name:name,location:location,cidrs:addressSpace.addressPrefixes}" -o jsonc

log "Subnets (show NAT association id):"
az network vnet subnet list -g "$RG" --vnet-name "$VNET" --query "[].{name:name,cidr:addressPrefix,nat:natGateway.id}" -o table

log "NAT Gateway:"
az network nat gateway show -g "$RG" -n "$NAT" --query "{name:name,publicIps:publicIpAddresses[].id}" -o jsonc

