#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 11-Create-GKE.sh (GCP)
#
# Creates:
# - Regional GKE cluster (VPC-native) in subnet-gke
# - Default node pool (core) with autoscaler
# - Spot node pool "workers" for burst workloads
#
# Design alignment:
# - Core supports always-on services.
# - Workers supports ingestion/outbox tasks at lower cost.
#
# Idempotency:
# - Cluster and node pools are created only if missing.
# ------------------------------------------------------------

PREFIX="gc-tkt-prod"
PROJECT_ID=""
REGION="us-central1"
CORE_NODES=3
MACHINE_TYPE="e2-standard-2"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix|-Prefix) PREFIX="$2"; shift 2;;
    --project-id|--ProjectId) PROJECT_ID="$2"; shift 2;;
    --region|-Region) REGION="$2"; shift 2;;
    --core-node-count|--CoreNodeCount) CORE_NODES="$2"; shift 2;;
    --machine-type|--MachineType) MACHINE_TYPE="$2"; shift 2;;
    *) die "Unknown argument: $1";;
  esac
done
[[ -n "$PROJECT_ID" ]] || die "--project-id is required."

require_cmd gcloud

gcloud config set project "$PROJECT_ID" >/dev/null

CLUSTER="$(to_gc_name "gke-$PREFIX")"
NET="$(to_gc_name "net-$PREFIX")"
SUB_GKE="$(to_gc_name "subnet-gke-$PREFIX")"

if gcloud container clusters describe "$CLUSTER" --region "$REGION" >/dev/null 2>&1; then
  log "GKE cluster exists: $CLUSTER"
else
  log "Creating GKE cluster: $CLUSTER"
  gcloud container clusters create "$CLUSTER" --region "$REGION" \
    --network "$NET" --subnetwork "$SUB_GKE" \
    --enable-ip-alias \
    --cluster-secondary-range-name pods \
    --services-secondary-range-name services \
    --num-nodes "$CORE_NODES" \
    --machine-type "$MACHINE_TYPE" \
    --enable-autoscaling --min-nodes 2 --max-nodes 4 \
    --workload-pool="$PROJECT_ID.svc.id.goog" \
    --labels="project=supportticketautomation,env=prod,prefix=$PREFIX" >/dev/null
fi

POOL="workers"
if gcloud container node-pools describe "$POOL" --cluster "$CLUSTER" --region "$REGION" >/dev/null 2>&1; then
  log "Node pool exists: $POOL"
else
  log "Creating spot worker pool: $POOL"
  gcloud container node-pools create "$POOL" --cluster "$CLUSTER" --region "$REGION" \
    --spot \
    --num-nodes 1 \
    --enable-autoscaling --min-nodes 0 --max-nodes 5 \
    --machine-type "$MACHINE_TYPE" \
    --node-labels="role=workers,env=prod" >/dev/null
fi

log "GKE provisioning complete."
log "Next: ./12-Validate-GKE.sh"

