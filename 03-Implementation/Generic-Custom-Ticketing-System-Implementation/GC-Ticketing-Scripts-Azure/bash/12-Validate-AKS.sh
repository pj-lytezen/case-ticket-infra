#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 12-Validate-AKS.sh (Azure)
#
# Validates AKS + ACR.
#
# Manual verification (Azure Portal):
# - Kubernetes services -> aks-<prefix>: provisioningState Succeeded
# - Node pools: default + workers
# - Container Registries: ACR exists
#
# Optional:
# - Configure kubectl:
#     az aks get-credentials -g rg-<prefix> -n aks-<prefix>
#   Then:
#     kubectl get nodes
# ------------------------------------------------------------

PREFIX="gc-tkt-prod"
LOCATION="eastus"
ACR_NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix|-Prefix) PREFIX="$2"; shift 2;;
    --location|-Location) LOCATION="$2"; shift 2;;
    --acr-name|--AcrName) ACR_NAME="$2"; shift 2;;
    *) die "Unknown argument: $1";;
  esac
done

require_cmd az

RG="$(rg_name "$PREFIX")"
SUFFIX="$(det_suffix)"
DEFAULT_ACR="$(to_global_name "acr${PREFIX}${SUFFIX}" 50)"
ACR="${ACR_NAME:-$DEFAULT_ACR}"

AKS="aks-$PREFIX"
az aks show -g "$RG" -n "$AKS" --query "{name:name,state:provisioningState,version:kubernetesVersion}" -o jsonc
az aks nodepool list -g "$RG" --cluster-name "$AKS" --query "[].{name:name,vmSize:vmSize,count:count,auto:enableAutoScaling,priority:scaleSetPriority}" -o table
az acr show -g "$RG" -n "$ACR" --query "{name:name,sku:sku.name}" -o jsonc

