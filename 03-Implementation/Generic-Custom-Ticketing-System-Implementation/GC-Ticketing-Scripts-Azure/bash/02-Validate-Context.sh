#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 02-Validate-Context.sh (Azure)
#
# Validation companion for 01-Context.sh.
#
# Manual verification (Azure Portal):
# - Confirm correct subscription and directory are selected.
# - Confirm RBAC permissions exist for: VNet, AKS, Postgres Flexible Server, Storage, Service Bus, Key Vault.
# ------------------------------------------------------------

parse_args_prefix_location "$@"

require_cmd az

sub_id="$(az_sub_id)"
log "OK: Azure CLI active subscription id = $sub_id"
log "Reminder: run 'az account set --subscription <id>' if you need to switch."

