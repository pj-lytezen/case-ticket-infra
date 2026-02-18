#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 11-Create-AKS.sh (Azure)
#
# Creates:
# - ACR (container registry)
# - AKS cluster in snet-aks with autoscaler enabled
# - Spot node pool "workers" for burst workloads
# - Monitoring addon wired to the Log Analytics workspace (created in 05)
#
# Design alignment:
# - Core pool is always-on for gateway/orchestrator/retrieval/evaluator/ticketing-api
# - Workers pool is spot for ingestion/outbox/etc.
#
# Idempotency:
# - If ACR/AKS/nodepool exist, creation is skipped.
# ------------------------------------------------------------

PREFIX="gc-tkt-prod"
LOCATION="eastus"
CORE_NODE_COUNT=3
CORE_NODE_SIZE="Standard_D2s_v5"
ACR_NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix|-Prefix) PREFIX="$2"; shift 2;;
    --location|-Location) LOCATION="$2"; shift 2;;
    --core-node-count|--CoreNodeCount) CORE_NODE_COUNT="$2"; shift 2;;
    --core-node-size|--CoreNodeVmSize) CORE_NODE_SIZE="$2"; shift 2;;
    --acr-name|--AcrName) ACR_NAME="$2"; shift 2;;
    *) die "Unknown argument: $1";;
  esac
done

require_cmd az

RG="$(rg_name "$PREFIX")"
ensure_rg "$RG" "$LOCATION"

SUFFIX="$(det_suffix)"
DEFAULT_ACR="$(to_global_name "acr${PREFIX}${SUFFIX}" 50)"
ACR="${ACR_NAME:-$DEFAULT_ACR}"

VNET="vnet-$PREFIX"
AKS_SUBNET="snet-aks"
AKS_SUBNET_ID="$(az network vnet subnet show -g "$RG" --vnet-name "$VNET" -n "$AKS_SUBNET" --query id -o tsv | tr -d '\r')"
[[ -n "$AKS_SUBNET_ID" ]] || die "Missing AKS subnet. Run ./03-Create-Network.sh first."

LAW="law-$PREFIX"
LAW_ID="$(az monitor log-analytics workspace show -g "$RG" -n "$LAW" --query id -o tsv | tr -d '\r' || true)"
[[ -n "$LAW_ID" ]] || die "Missing Log Analytics workspace $LAW. Run ./05-Create-Security.sh first."

# ACR
if az acr show -g "$RG" -n "$ACR" >/dev/null 2>&1; then
  log "ACR exists: $ACR"
else
  log "Creating ACR: $ACR"
  az acr create -g "$RG" -n "$ACR" --sku Standard --admin-enabled false \
    --tags Project=SupportTicketAutomation Prefix="$PREFIX" >/dev/null
fi

AKS="aks-$PREFIX"
if az aks show -g "$RG" -n "$AKS" >/dev/null 2>&1; then
  log "AKS exists: $AKS"
else
  log "Creating AKS cluster: $AKS"
  az aks create -g "$RG" -n "$AKS" -l "$LOCATION" \
    --enable-managed-identity \
    --node-count "$CORE_NODE_COUNT" \
    --node-vm-size "$CORE_NODE_SIZE" \
    --enable-cluster-autoscaler --min-count 2 --max-count 4 \
    --network-plugin azure \
    --vnet-subnet-id "$AKS_SUBNET_ID" \
    --attach-acr "$ACR" \
    --enable-addons monitoring \
    --workspace-resource-id "$LAW_ID" \
    --tags Project=SupportTicketAutomation Prefix="$PREFIX" >/dev/null
fi

# Spot node pool for workers.
POOL="workers"
if az aks nodepool show -g "$RG" --cluster-name "$AKS" -n "$POOL" >/dev/null 2>&1; then
  log "Nodepool exists: $POOL"
else
  log "Adding spot nodepool: $POOL"
  az aks nodepool add -g "$RG" --cluster-name "$AKS" -n "$POOL" \
    --node-count 1 \
    --enable-cluster-autoscaler --min-count 0 --max-count 5 \
    --priority Spot --eviction-policy Delete --spot-max-price -1 \
    --node-vm-size "$CORE_NODE_SIZE" \
    --labels role=workers env=prod >/dev/null
fi

log "AKS provisioning complete."
log "Next: ./12-Validate-AKS.sh"

