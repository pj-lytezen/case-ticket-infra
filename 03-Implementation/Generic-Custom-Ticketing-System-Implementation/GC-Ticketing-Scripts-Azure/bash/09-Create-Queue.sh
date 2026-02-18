#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 09-Create-Queue.sh (Azure)
#
# Creates Service Bus components:
# - Namespace (Standard tier)
# - Queue: jobs
#
# Design note:
# - Service Bus has a built-in DLQ for each queue; you don’t create a separate DLQ resource.
#
# Idempotency:
# - Namespace and queue are checked before creation.
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
ensure_rg "$RG" "$LOCATION"

SUFFIX="$(det_suffix)"
DEFAULT_NS="$(to_global_name "sb${PREFIX}${SUFFIX}" 50)"
NS="${SB_NS:-$DEFAULT_NS}"

if az servicebus namespace show -g "$RG" -n "$NS" >/dev/null 2>&1; then
  log "Service Bus namespace exists: $NS"
else
  log "Creating Service Bus namespace: $NS"
  az servicebus namespace create -g "$RG" -n "$NS" -l "$LOCATION" --sku Standard \
    --tags Project=SupportTicketAutomation Prefix="$PREFIX" >/dev/null
fi

QUEUE="jobs"
if az servicebus queue show -g "$RG" --namespace-name "$NS" -n "$QUEUE" >/dev/null 2>&1; then
  log "Queue exists: $QUEUE"
else
  log "Creating queue: $QUEUE"
  az servicebus queue create -g "$RG" --namespace-name "$NS" -n "$QUEUE" \
    --max-delivery-count 5 \
    --enable-dead-lettering-on-message-expiration true >/dev/null
fi

log "Queueing complete."
log "Namespace: $NS"
log "Queue    : $QUEUE (DLQ is built-in)"
log "Next: ./10-Validate-Queue.sh"

