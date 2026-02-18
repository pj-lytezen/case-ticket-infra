#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 12-Validate-GKE.sh (GCP)
#
# Manual verification (GCP Console):
# - Kubernetes Engine -> Clusters: confirm cluster exists and is healthy
# - Node pools: default + workers
#
# Optional:
# - Get kubectl credentials:
#     gcloud container clusters get-credentials gke-<prefix> --region <region>
#   Then:
#     kubectl get nodes
# ------------------------------------------------------------

parse_args_prefix_project_region_zone "$@"

require_cmd gcloud

gcloud config set project "$PROJECT_ID" >/dev/null

CLUSTER="$(to_gc_name "gke-$PREFIX")"
gcloud container clusters describe "$CLUSTER" --region "$REGION" --format="yaml(name,status,location,network,subnetwork)" | sed 's/^/  /'
gcloud container node-pools list --cluster "$CLUSTER" --region "$REGION" --format="table(name,status,config.machineType,config.spot)" || true

