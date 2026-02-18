#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 07-Create-Storage.sh (Azure)
#
# Creates:
# - Storage account (StorageV2) for docs/attachments/audit artifacts
# - Blob containers: docs, attachments, audit
#
# Idempotency:
# - Storage account name is deterministic (prefix + subscription suffix) unless overridden.
# - Containers are created only if missing.
# ------------------------------------------------------------

PREFIX="gc-tkt-prod"
LOCATION="eastus"
SKU="Standard_LRS"
STORAGE_NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix|-Prefix) PREFIX="$2"; shift 2;;
    --location|-Location) LOCATION="$2"; shift 2;;
    --sku|--Sku) SKU="$2"; shift 2;;
    --storage-account-name|--StorageAccountName) STORAGE_NAME="$2"; shift 2;;
    *) die "Unknown argument: $1";;
  esac
done

require_cmd az

RG="$(rg_name "$PREFIX")"
ensure_rg "$RG" "$LOCATION"

SUFFIX="$(det_suffix)"
DEFAULT_ST="$(to_global_name "st${PREFIX}${SUFFIX}" 24)"
ST="${STORAGE_NAME:-$DEFAULT_ST}"

if az storage account show -g "$RG" -n "$ST" >/dev/null 2>&1; then
  log "Storage account exists: $ST"
else
  log "Creating storage account: $ST ($SKU)"
  az storage account create -g "$RG" -n "$ST" -l "$LOCATION" \
    --kind StorageV2 --sku "$SKU" \
    --min-tls-version TLS1_2 \
    --https-only true \
    --allow-blob-public-access false \
    --tags Project=SupportTicketAutomation Prefix="$PREFIX" >/dev/null
fi

# Create containers (login-based auth is simplest for CLI users).
for c in docs attachments audit; do
  exists="$(az storage container exists --account-name "$ST" -n "$c" --auth-mode login --query exists -o tsv | tr -d '\r')"
  if [[ "$exists" == "true" ]]; then
    log "Container exists: $c"
  else
    log "Creating container: $c"
    az storage container create --account-name "$ST" -n "$c" --auth-mode login >/dev/null
  fi
done

log "Storage complete."
log "Storage account: $ST"
log "Next: ./08-Validate-Storage.sh"

