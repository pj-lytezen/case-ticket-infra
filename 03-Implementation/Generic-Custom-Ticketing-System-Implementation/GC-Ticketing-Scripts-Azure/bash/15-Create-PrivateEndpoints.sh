#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 15-Create-PrivateEndpoints.sh (Azure)
#
# Creates private endpoints (recommended) to reduce NAT usage and improve security:
# - Storage account (Blob)
# - Key Vault
#
# Why (cost saving):
# - In private-subnet designs, NAT Gateway can incur per-GB processing charges.
# - Private Endpoints keep traffic on Azure backbone and often reduce NAT usage.
#
# Idempotency:
# - Checks for existing private endpoints by name and reuses them.
# - Ensures private DNS zones exist and are linked to the VNet.
# ------------------------------------------------------------

PREFIX="gc-tkt-prod"
LOCATION="eastus"
STORAGE_NAME=""
KV_NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix|-Prefix) PREFIX="$2"; shift 2;;
    --location|-Location) LOCATION="$2"; shift 2;;
    --storage-account-name|--StorageAccountName) STORAGE_NAME="$2"; shift 2;;
    --keyvault-name|--KeyVaultName) KV_NAME="$2"; shift 2;;
    *) die "Unknown argument: $1";;
  esac
done

require_cmd az

RG="$(rg_name "$PREFIX")"
ensure_rg "$RG" "$LOCATION"

SUFFIX="$(det_suffix)"
DEFAULT_ST="$(to_global_name "st${PREFIX}${SUFFIX}" 24)"
DEFAULT_KV="$(to_global_name "kv${PREFIX}${SUFFIX}" 24)"
ST="${STORAGE_NAME:-$DEFAULT_ST}"
KV="${KV_NAME:-$DEFAULT_KV}"

VNET="vnet-$PREFIX"
PE_SUBNET="snet-pe"

VNET_ID="$(az network vnet show -g "$RG" -n "$VNET" --query id -o tsv | tr -d '\r')"
PE_SUBNET_ID="$(az network vnet subnet show -g "$RG" --vnet-name "$VNET" -n "$PE_SUBNET" --query id -o tsv | tr -d '\r')"
[[ -n "$PE_SUBNET_ID" ]] || die "Missing $PE_SUBNET. Run ./03-Create-Network.sh."

ensure_dns_zone_and_link() {
  local zone="$1" link="$2"
  if az network private-dns zone show -g "$RG" -n "$zone" >/dev/null 2>&1; then
    :
  else
    log "Creating Private DNS zone: $zone"
    az network private-dns zone create -g "$RG" -n "$zone" >/dev/null
  fi
  if az network private-dns link vnet show -g "$RG" -z "$zone" -n "$link" >/dev/null 2>&1; then
    :
  else
    log "Linking DNS zone to VNet: $zone"
    az network private-dns link vnet create -g "$RG" -z "$zone" -n "$link" -v "$VNET_ID" -e false >/dev/null
  fi
}

ensure_private_endpoint() {
  local pe_name="$1" target_id="$2" group_id="$3" zone="$4"
  if az network private-endpoint show -g "$RG" -n "$pe_name" >/dev/null 2>&1; then
    log "Private endpoint exists: $pe_name"
  else
    log "Creating private endpoint: $pe_name (groupId=$group_id)"
    az network private-endpoint create -g "$RG" -n "$pe_name" -l "$LOCATION" \
      --subnet "$PE_SUBNET_ID" \
      --private-connection-resource-id "$target_id" \
      --group-id "$group_id" \
      --connection-name "$pe_name" >/dev/null
  fi

  # DNS zone group attaches the endpoint to a Private DNS zone for auto-record creation.
  local zone_group="zg-$pe_name"
  if az network private-endpoint dns-zone-group show -g "$RG" --endpoint-name "$pe_name" -n "$zone_group" >/dev/null 2>&1; then
    :
  else
    zone_id="$(az network private-dns zone show -g "$RG" -n "$zone" --query id -o tsv | tr -d '\r')"
    log "Creating DNS zone group for $pe_name"
    az network private-endpoint dns-zone-group create -g "$RG" --endpoint-name "$pe_name" -n "$zone_group" \
      --private-dns-zone "$zone_id" --zone-name "$zone" >/dev/null
  fi
}

# Storage (Blob) private endpoint
BLOB_ZONE="privatelink.blob.core.windows.net"
ensure_dns_zone_and_link "$BLOB_ZONE" "link-$PREFIX-blob"
ST_ID="$(az storage account show -g "$RG" -n "$ST" --query id -o tsv | tr -d '\r')"
ensure_private_endpoint "pe-$PREFIX-blob" "$ST_ID" "blob" "$BLOB_ZONE"

# Key Vault private endpoint
KV_ZONE="privatelink.vaultcore.azure.net"
ensure_dns_zone_and_link "$KV_ZONE" "link-$PREFIX-kv"
KV_ID="$(az keyvault show -g "$RG" -n "$KV" --query id -o tsv | tr -d '\r')"
ensure_private_endpoint "pe-$PREFIX-kv" "$KV_ID" "vault" "$KV_ZONE"

log "Private endpoints complete."
log "Next: ./16-Validate-PrivateEndpoints.sh"

