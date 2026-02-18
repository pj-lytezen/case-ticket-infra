#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 01-Context.sh (Azure)
#
# Purpose:
# - Pre-flight: confirm Azure CLI is installed and authenticated.
# - Print subscription + tenant + identity to avoid deploying to the wrong subscription.
#
# Idempotency:
# - No cloud resources created here.
# ------------------------------------------------------------

parse_args_prefix_location "$@"

require_cmd az

log "Prefix=$PREFIX Location=$LOCATION"

acct_name="$(az account show --query name -o tsv | tr -d '\r')"
acct_id="$(az account show --query id -o tsv | tr -d '\r')"
tenant_id="$(az account show --query tenantId -o tsv | tr -d '\r')"
user_name="$(az account show --query user.name -o tsv | tr -d '\r')"
user_type="$(az account show --query user.type -o tsv | tr -d '\r')"

log "Subscription: $acct_name ($acct_id)"
log "Tenant      : $tenant_id"
log "User/Service: $user_name ($user_type)"

log "Context OK. Next: ./03-Create-Network.sh"

