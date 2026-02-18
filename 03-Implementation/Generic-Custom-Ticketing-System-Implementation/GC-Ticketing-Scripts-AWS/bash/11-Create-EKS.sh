#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 11-Create-EKS.sh
#
# Creates:
# - IAM roles for EKS cluster and nodes
# - EKS cluster (<prefix>-eks) in private app subnets
# - Managed node groups:
#     - core (on-demand; always-on)
#     - workers (spot; burst compute for ingestion/outbox)
#
# Why:
# - Matches design: small always-on footprint + cheap workers.
#
# Idempotency:
# - If cluster/nodegroups/roles exist, creation is skipped.
# ------------------------------------------------------------

PREFIX="gc-tkt-prod"
ENVIRONMENT="prod"
REGION="us-east-1"
K8S_VERSION="1.29"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix|-Prefix) PREFIX="$2"; shift 2;;
    --environment|--env) ENVIRONMENT="$2"; shift 2;;
    --region|-Region) REGION="$2"; shift 2;;
    --kubernetes-version|--k8s-version) K8S_VERSION="$2"; shift 2;;
    *) die "Unknown argument: $1";;
  esac
done

require_cmd aws
require_cmd jq

read -r AZ1 AZ2 <<<"$(get_two_azs "$REGION")"
VPC_ID="$(find_vpc_id_by_name "$REGION" "$PREFIX-vpc")"
[[ -n "$VPC_ID" ]] || die "Missing VPC. Run ./03-Create-Network.sh first."

APP1="$(find_subnet_id_by_name "$REGION" "$VPC_ID" "$PREFIX-app-$AZ1")"
APP2="$(find_subnet_id_by_name "$REGION" "$VPC_ID" "$PREFIX-app-$AZ2")"
[[ -n "$APP1" && -n "$APP2" ]] || die "Missing app subnets. Run ./03-Create-Network.sh."

ensure_iam_role() {
  local role_name="$1"
  local trust_json="$2"
  if aws iam get-role --role-name "$role_name" >/dev/null 2>&1; then
    log "IAM role exists: $role_name"
    aws iam get-role --role-name "$role_name" --query 'Role.Arn' --output text
    return
  fi
  log "Creating IAM role: $role_name"
  tmp="$(mktemp)"
  printf '%s' "$trust_json" >"$tmp"
  aws iam create-role --role-name "$role_name" --assume-role-policy-document "file://$tmp" --query 'Role.Arn' --output text
}

attach_policy() {
  local role_name="$1" policy_arn="$2"
  # IAM attach-role-policy is idempotent.
  aws iam attach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" >/dev/null
}

CLUSTER_ROLE_NAME="$PREFIX-eks-cluster-role"
CLUSTER_TRUST='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"eks.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
CLUSTER_ROLE_ARN="$(ensure_iam_role "$CLUSTER_ROLE_NAME" "$CLUSTER_TRUST")"
attach_policy "$CLUSTER_ROLE_NAME" "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"

NODE_ROLE_NAME="$PREFIX-eks-node-role"
NODE_TRUST='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
NODE_ROLE_ARN="$(ensure_iam_role "$NODE_ROLE_NAME" "$NODE_TRUST")"
attach_policy "$NODE_ROLE_NAME" "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
attach_policy "$NODE_ROLE_NAME" "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
attach_policy "$NODE_ROLE_NAME" "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"

# Cluster security group so RDS can later allow inbound from the cluster (tightening step).
SG_NAME="$PREFIX-eks-cluster-sg"
SG_ID="$(find_sg_id_by_group_name "$REGION" "$VPC_ID" "$SG_NAME")"
if [[ -z "$SG_ID" ]]; then
  log "Creating security group: $SG_NAME"
  SG_ID="$(aws ec2 create-security-group --region "$REGION" --vpc-id "$VPC_ID" --group-name "$SG_NAME" \
    --description "$PREFIX EKS cluster SG" --query GroupId --output text)"
  aws ec2 create-tags --region "$REGION" --resources "$SG_ID" --tags \
    "Key=Name,Value=$SG_NAME" $(default_tags_kv "$PREFIX" "$ENVIRONMENT") >/dev/null

  # Allow HTTPS to the cluster endpoints from within the VPC CIDR.
  VPC_CIDR="$(aws ec2 describe-vpcs --region "$REGION" --vpc-ids "$VPC_ID" --query 'Vpcs[0].CidrBlock' --output text)"
  aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$SG_ID" \
    --ip-permissions "IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges=[{CidrIp=$VPC_CIDR,Description=VPC-internal}]" \
    >/dev/null 2>&1 || true
else
  log "Security group exists: $SG_NAME ($SG_ID)"
fi

CLUSTER_NAME="$PREFIX-eks"
if aws eks describe-cluster --region "$REGION" --name "$CLUSTER_NAME" >/dev/null 2>&1; then
  status="$(aws eks describe-cluster --region "$REGION" --name "$CLUSTER_NAME" --query 'cluster.status' --output text)"
  log "EKS cluster exists: $CLUSTER_NAME status=$status"
else
  log "Creating EKS cluster: $CLUSTER_NAME (version $K8S_VERSION)"

  # Note: EKS uses a single cluster security group + subnet list.
  # We enable both public and private endpoint access initially to keep operations simple.
  # Later, you can restrict to private endpoint only once your access path is fully planned.
  aws eks create-cluster --region "$REGION" \
    --name "$CLUSTER_NAME" \
    --kubernetes-version "$K8S_VERSION" \
    --role-arn "$CLUSTER_ROLE_ARN" \
    --resources-vpc-config "subnetIds=$APP1,$APP2,securityGroupIds=$SG_ID,endpointPublicAccess=true,endpointPrivateAccess=true" \
    >/dev/null
fi

log "Waiting for cluster to become ACTIVE..."
aws eks wait cluster-active --region "$REGION" --name "$CLUSTER_NAME"

ensure_nodegroup() {
  local ng_name="$1" capacity="$2" min="$3" desired="$4" max="$5" instance_type="$6"
  if aws eks describe-nodegroup --region "$REGION" --cluster-name "$CLUSTER_NAME" --nodegroup-name "$ng_name" >/dev/null 2>&1; then
    log "Nodegroup exists: $ng_name"
    return
  fi
  log "Creating nodegroup: $ng_name ($capacity) desired=$desired"

  # IMPORTANT: `--subnets` expects SPACE-separated subnet IDs (not a comma-separated string).
  aws eks create-nodegroup --region "$REGION" \
    --cluster-name "$CLUSTER_NAME" \
    --nodegroup-name "$ng_name" \
    --node-role "$NODE_ROLE_ARN" \
    --subnets "$APP1" "$APP2" \
    --scaling-config "minSize=$min,maxSize=$max,desiredSize=$desired" \
    --capacity-type "$capacity" \
    --disk-size 50 \
    --instance-types "$instance_type" \
    --labels "role=$ng_name,env=$ENVIRONMENT" \
    --tags "Project=SupportTicketAutomation,Environment=$ENVIRONMENT,Prefix=$PREFIX,Name=$PREFIX-$ng_name" \
    >/dev/null
}

ensure_nodegroup core ON_DEMAND 2 3 4 t3.medium
ensure_nodegroup workers SPOT 0 1 5 t3.medium

log "Waiting for nodegroups to become ACTIVE..."
aws eks wait nodegroup-active --region "$REGION" --cluster-name "$CLUSTER_NAME" --nodegroup-name core
aws eks wait nodegroup-active --region "$REGION" --cluster-name "$CLUSTER_NAME" --nodegroup-name workers

log "EKS provisioning complete."
log "Next: ./12-Validate-EKS.sh"

