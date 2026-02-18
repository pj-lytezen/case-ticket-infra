#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 13-Create-Postgres.sh (Azure)
#
# Creates Azure Database for PostgreSQL Flexible Server (private access):
# - Private DNS zone: privatelink.postgres.database.azure.com
# - VNet link to vnet-<prefix>
# - Postgres flexible server in delegated subnet snet-pg
# - Database: gc_ticketing
#
# Why:
# - Matches design: PostgreSQL is the primary store and powers Hybrid RAG (FTS + pgvector).
# - Private access reduces exposure and can reduce unnecessary egress.
#
# Idempotency:
# - Checks DNS zone, link, server, and database existence before creating.
#
# Important:
# - Azure CLI flags for private access can vary by CLI version.
#   This script attempts the “subnet id + private dns zone id” pattern first.
#   If it fails, it prints an alternate command you can try manually.
# ------------------------------------------------------------

PREFIX="gc-tkt-prod"
LOCATION="eastus"
SKU_NAME="Standard_D4s_v3"
TIER="GeneralPurpose"
STORAGE_GB=256
PG_NAME=""
KV_NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix|-Prefix) PREFIX="$2"; shift 2;;
    --location|-Location) LOCATION="$2"; shift 2;;
    --sku-name|--SkuName) SKU_NAME="$2"; shift 2;;
    --tier|--Tier) TIER="$2"; shift 2;;
    --storage-gb|--StorageGb) STORAGE_GB="$2"; shift 2;;
    --postgres-name|--PostgresServerName) PG_NAME="$2"; shift 2;;
    --keyvault-name|--KeyVaultName) KV_NAME="$2"; shift 2;;
    *) die "Unknown argument: $1";;
  esac
done

require_cmd az

RG="$(rg_name "$PREFIX")"
ensure_rg "$RG" "$LOCATION"

SUFFIX="$(det_suffix)"
DEFAULT_PG="$(to_global_name "pg${PREFIX}${SUFFIX}" 63)"
PG="${PG_NAME:-$DEFAULT_PG}"
DEFAULT_KV="$(to_global_name "kv${PREFIX}${SUFFIX}" 24)"
KV="${KV_NAME:-$DEFAULT_KV}"

VNET="vnet-$PREFIX"
PG_SUBNET="snet-pg"

# Credentials come from Key Vault (created in 05).
ADMIN_USER="$(az keyvault secret show --vault-name "$KV" -n pg-admin-user --query value -o tsv | tr -d '\r')"
ADMIN_PASS="$(az keyvault secret show --vault-name "$KV" -n pg-admin-password --query value -o tsv | tr -d '\r')"

DNS_ZONE="privatelink.postgres.database.azure.com"

if az network private-dns zone show -g "$RG" -n "$DNS_ZONE" >/dev/null 2>&1; then
  log "Private DNS zone exists: $DNS_ZONE"
else
  log "Creating private DNS zone: $DNS_ZONE"
  az network private-dns zone create -g "$RG" -n "$DNS_ZONE" >/dev/null
fi

DNS_ZONE_ID="$(az network private-dns zone show -g "$RG" -n "$DNS_ZONE" --query id -o tsv | tr -d '\r')"
VNET_ID="$(az network vnet show -g "$RG" -n "$VNET" --query id -o tsv | tr -d '\r')"

# Link DNS zone to VNet.
LINK="link-${PREFIX}-pg"
if az network private-dns link vnet show -g "$RG" -z "$DNS_ZONE" -n "$LINK" >/dev/null 2>&1; then
  log "DNS link exists: $LINK"
else
  log "Creating DNS link: $LINK"
  az network private-dns link vnet create -g "$RG" -z "$DNS_ZONE" -n "$LINK" -v "$VNET_ID" -e false >/dev/null
fi

PG_SUBNET_ID="$(az network vnet subnet show -g "$RG" --vnet-name "$VNET" -n "$PG_SUBNET" --query id -o tsv | tr -d '\r')"
[[ -n "$PG_SUBNET_ID" ]] || die "Missing delegated subnet $PG_SUBNET. Run ./03-Create-Network.sh first."

if az postgres flexible-server show -g "$RG" -n "$PG" >/dev/null 2>&1; then
  log "Postgres server exists: $PG"
else
  log "Creating Postgres Flexible Server: $PG (private access)"
  if ! az postgres flexible-server create -g "$RG" -n "$PG" -l "$LOCATION" \
    --tier "$TIER" --sku-name "$SKU_NAME" --storage-size "$STORAGE_GB" \
    --admin-user "$ADMIN_USER" --admin-password "$ADMIN_PASS" \
    --public-access none \
    --subnet "$PG_SUBNET_ID" \
    --private-dns-zone "$DNS_ZONE_ID" \
    --tags Project=SupportTicketAutomation Prefix="$PREFIX" >/dev/null; then
    warn "Postgres creation failed. Azure CLI private networking flags can vary by CLI version."
    warn "Try this alternate form manually (subnet name + vnet name):"
    warn "  az postgres flexible-server create -g $RG -n $PG -l $LOCATION --tier $TIER --sku-name $SKU_NAME --storage-size $STORAGE_GB --admin-user $ADMIN_USER --admin-password <password> --public-access none --vnet $VNET --subnet $PG_SUBNET --private-dns-zone $DNS_ZONE"
    exit 1
  fi
fi

DB="gc_ticketing"
if az postgres flexible-server db show -g "$RG" -s "$PG" -d "$DB" >/dev/null 2>&1; then
  log "Database exists: $DB"
else
  log "Creating database: $DB"
  az postgres flexible-server db create -g "$RG" -s "$PG" -d "$DB" >/dev/null
fi

log "Postgres provisioning complete."
log "Next: ./14-Validate-Postgres.sh"

