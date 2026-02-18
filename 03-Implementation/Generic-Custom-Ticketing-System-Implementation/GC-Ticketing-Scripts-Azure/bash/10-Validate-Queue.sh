#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 10-Validate-Queue.sh (Azure)
#
# Validates Service Bus namespace and queue.
#
# Manual verification (Azure Portal):
# - Service Bus -> Namespaces: confirm namespace exists
# - Queues: confirm “jobs” exists and DLQ settings are configured
# ------------------------------------------------------------

PREFIX="gc-tkt-prod"
LOCATION="eastus"
SB_NS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix|-Prefix) PREFIX="$2"; shift 2;;
    --location|-Location) LOCATION="$2"; shift 2;;
    --servicebus-namespace|--ServiceBusNamespaceName) SB_NS="$2"; shift 2;;
    *) die "Unknown argument: $1";;
  esac
done

require_cmd az

RG="$(rg_name "$PREFIX")"
SUFFIX="$(det_suffix)"
DEFAULT_NS="$(to_global_name "sb${PREFIX}${SUFFIX}" 50)"
NS="${SB_NS:-$DEFAULT_NS}"

az servicebus namespace show -g "$RG" -n "$NS" --query "{name:name,sku:sku.name,location:location}" -o jsonc
az servicebus queue show -g "$RG" --namespace-name "$NS" -n jobs \
  --query "{name:name,maxDelivery:maxDeliveryCount,deadLetterOnExpire:deadLetteringOnMessageExpiration}" -o jsonc

