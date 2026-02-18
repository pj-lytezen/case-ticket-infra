#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 05-Create-Security.sh (Azure)
#
# Creates:
# - Log Analytics workspace (for AKS monitoring + centralized logs)
# - Key Vault (RBAC-enabled) for secrets
# - Initial secrets: pg-admin-user, pg-admin-password, app-config-json
#
# Idempotency:
# - If workspace/vault/secrets exist, script reuses them and does not overwrite.
#
# Notes:
# - Key Vault names are globally unique. You can override with --keyvault-name.
# - RBAC assignment may require directory permissions; if it fails, follow the manual steps printed.
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
ensure_rg "$RG" "$LOCATION"

SUFFIX="$(det_suffix)"
DEFAULT_KV="$(to_global_name "kv${PREFIX}${SUFFIX}" 24)"
KV="${KEYVAULT_NAME:-$DEFAULT_KV}"
LAW="law-$PREFIX"

if az monitor log-analytics workspace show -g "$RG" -n "$LAW" >/dev/null 2>&1; then
  log "Log Analytics workspace exists: $LAW"
else
  log "Creating Log Analytics workspace: $LAW"
  az monitor log-analytics workspace create -g "$RG" -n "$LAW" -l "$LOCATION" \
    --tags Project=SupportTicketAutomation Prefix="$PREFIX" >/dev/null
fi

if az keyvault show -g "$RG" -n "$KV" >/dev/null 2>&1; then
  log "Key Vault exists: $KV"
else
  log "Creating Key Vault: $KV (RBAC authorization enabled)"
  az keyvault create -g "$RG" -n "$KV" -l "$LOCATION" \
    --enable-rbac-authorization true \
    --sku standard \
    --tags Project=SupportTicketAutomation Prefix="$PREFIX" >/dev/null

  # Grant the current signed-in user the ability to manage secrets.
  # This frequently fails in locked-down enterprises; if it fails, do it manually in Portal:
  #   Key Vault -> Access control (IAM) -> Add role assignment -> "Key Vault Secrets Officer"
  # Scope: the Key Vault resource.
  if principal_id="$(az ad signed-in-user show --query id -o tsv 2>/dev/null | tr -d '\r')"; then
    scope="$(az keyvault show -g "$RG" -n "$KV" --query id -o tsv | tr -d '\r')"
    if ! az role assignment create --assignee-object-id "$principal_id" --assignee-principal-type User \
      --role "Key Vault Secrets Officer" --scope "$scope" >/dev/null 2>&1; then
      warn "Could not auto-assign Key Vault role. Assign manually: Key Vault Secrets Officer on $KV."
    else
      log "Assigned Key Vault Secrets Officer to current user."
    fi
  else
    warn "Could not determine signed-in user id. You may need to assign Key Vault RBAC manually."
  fi
fi

random_pw() { LC_ALL=C tr -dc 'A-HJ-NP-Za-km-z2-9' </dev/urandom | head -c 28; }

ensure_kv_secret() {
  local name="$1" value="$2"
  if az keyvault secret show --vault-name "$KV" -n "$name" >/dev/null 2>&1; then
    log "Secret exists: $name"
    return
  fi
  log "Creating secret: $name"
  az keyvault secret set --vault-name "$KV" -n "$name" --value "$value" >/dev/null
}

ensure_kv_secret "pg-admin-user" "pgadmin"
ensure_kv_secret "pg-admin-password" "$(random_pw)"
ensure_kv_secret "app-config-json" '{"environment":"prod","notes":"fill after provisioning"}'

log "Security complete."
log "Key Vault     : $KV"
log "Log Analytics : $LAW"
log "Next: ./06-Validate-Security.sh"

