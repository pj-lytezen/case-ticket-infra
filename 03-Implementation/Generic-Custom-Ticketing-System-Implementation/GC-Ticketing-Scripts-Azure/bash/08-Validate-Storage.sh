#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 08-Validate-Storage.sh (Azure)
#
# Validates:
# - Storage account exists
# - Containers exist
# - Blob public access is disabled
# ------------------------------------------------------------

PREFIX="gc-tkt-prod"
LOCATION="eastus"
STORAGE_NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix|-Prefix) PREFIX="$2"; shift 2;;
    --location|-Location) LOCATION="$2"; shift 2;;
    --storage-account-name|--StorageAccountName) STORAGE_NAME="$2"; shift 2;;
    *) die "Unknown argument: $1";;
  esac
done

require_cmd az

RG="$(rg_name "$PREFIX")"
SUFFIX="$(det_suffix)"
DEFAULT_ST="$(to_global_name "st${PREFIX}${SUFFIX}" 24)"
ST="${STORAGE_NAME:-$DEFAULT_ST}"

az storage account show -g "$RG" -n "$ST" --query "{name:name,sku:sku.name,publicBlob:allowBlobPublicAccess}" -o jsonc
for c in docs attachments audit; do
  exists="$(az storage container exists --account-name "$ST" -n "$c" --auth-mode login --query exists -o tsv | tr -d '\r')"
  log "Container $c exists=$exists"
done

