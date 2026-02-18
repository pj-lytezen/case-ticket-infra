#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 12-Validate-EKS.sh
#
# Validates EKS cluster + nodegroups.
#
# Manual verification (AWS Console):
# - EKS -> Clusters: confirm <prefix>-eks is ACTIVE
# - Node groups: confirm core and workers are ACTIVE
#
# Optional:
# - Configure kubectl:
#     aws eks update-kubeconfig --region <region> --name <cluster>
#   Then:
#     kubectl get nodes
# ------------------------------------------------------------

parse_args_prefix_env_region "$@"

require_cmd aws

CLUSTER_NAME="$PREFIX-eks"
aws eks describe-cluster --region "$REGION" --name "$CLUSTER_NAME" \
  --query 'cluster.{name:name,status:status,version:version,vpc:resourcesVpcConfig.vpcId}' --output table

ngs="$(aws eks list-nodegroups --region "$REGION" --cluster-name "$CLUSTER_NAME" --query 'nodegroups' --output text)"
log "Nodegroups: $ngs"
for ng in $ngs; do
  aws eks describe-nodegroup --region "$REGION" --cluster-name "$CLUSTER_NAME" --nodegroup-name "$ng" \
    --query 'nodegroup.{name:nodegroupName,status:status,desired:scalingConfig.desiredSize}' --output table
done

