#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 15-Create-VpcEndpoints.sh
#
# Creates VPC endpoints to reduce NAT Gateway data-processing cost and improve security:
# - Gateway endpoint: S3
# - Interface endpoints: SQS, Secrets Manager, CloudWatch Logs, ECR (api+dkr), STS
#
# Why it matters (cost + security):
# - In private subnet architectures, NAT per-GB processing can be a major recurring cost.
# - Private endpoints keep traffic on AWS backbone and reduce exposure.
#
# Idempotency:
# - Endpoint existence is checked by (VPC, service-name).
# ------------------------------------------------------------

parse_args_prefix_env_region "$@"

require_cmd aws

read -r AZ1 AZ2 <<<"$(get_two_azs "$REGION")"
VPC_ID="$(find_vpc_id_by_name "$REGION" "$PREFIX-vpc")"
[[ -n "$VPC_ID" ]] || die "Missing VPC. Run ./03-Create-Network.sh."

APP1="$(find_subnet_id_by_name "$REGION" "$VPC_ID" "$PREFIX-app-$AZ1")"
APP2="$(find_subnet_id_by_name "$REGION" "$VPC_ID" "$PREFIX-app-$AZ2")"
[[ -n "$APP1" && -n "$APP2" ]] || die "Missing app subnets."

RT1="$(find_route_table_id_by_name "$REGION" "$VPC_ID" "$PREFIX-rt-private-$AZ1")"
RT2="$(find_route_table_id_by_name "$REGION" "$VPC_ID" "$PREFIX-rt-private-$AZ2")"
[[ -n "$RT1" && -n "$RT2" ]] || die "Missing private route tables. Run ./03-Create-Network.sh."

VPC_CIDR="$(aws ec2 describe-vpcs --region "$REGION" --vpc-ids "$VPC_ID" --query 'Vpcs[0].CidrBlock' --output text)"

ensure_vpce_sg() {
  local sg_name="$PREFIX-vpce-sg"
  local sg_id
  sg_id="$(find_sg_id_by_group_name "$REGION" "$VPC_ID" "$sg_name")"
  if [[ -n "$sg_id" ]]; then
    printf '%s' "$sg_id"
    return
  fi
  log "Creating VPC endpoint SG: $sg_name"
  sg_id="$(aws ec2 create-security-group --region "$REGION" --vpc-id "$VPC_ID" \
    --group-name "$sg_name" --description "$PREFIX VPC endpoints SG" \
    --query GroupId --output text)"
  aws ec2 create-tags --region "$REGION" --resources "$sg_id" --tags \
    "Key=Name,Value=$sg_name" $(default_tags_kv "$PREFIX" "$ENVIRONMENT") >/dev/null
  aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$sg_id" \
    --ip-permissions "IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges=[{CidrIp=$VPC_CIDR,Description=VPC-internal}]" \
    >/dev/null 2>&1 || true
  printf '%s' "$sg_id"
}

endpoint_exists() {
  local svc="$1"
  local id
  id="$(aws ec2 describe-vpc-endpoints --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=service-name,Values=$svc" \
    --query 'VpcEndpoints[?State!=`deleted`][0].VpcEndpointId' --output text)"
  id="$(none_to_empty "$id")"
  [[ -n "$id" ]]
}

# S3 Gateway endpoint (uses route tables, not subnets).
S3_SVC="com.amazonaws.$REGION.s3"
if endpoint_exists "$S3_SVC"; then
  log "S3 gateway endpoint exists."
else
  log "Creating S3 gateway endpoint"
  aws ec2 create-vpc-endpoint --region "$REGION" \
    --vpc-id "$VPC_ID" \
    --vpc-endpoint-type Gateway \
    --service-name "$S3_SVC" \
    --route-table-ids "$RT1" "$RT2" \
    --tag-specifications "$(tag_spec vpc-endpoint "$PREFIX-vpce-s3" "$PREFIX" "$ENVIRONMENT")" \
    >/dev/null
fi

create_interface_vpce() {
  local svc_short="$1" name_tag="$2"
  local svc="com.amazonaws.$REGION.$svc_short"
  if endpoint_exists "$svc"; then
    log "Interface endpoint exists for $svc_short"
    return
  fi
  local sg_id
  sg_id="$(ensure_vpce_sg)"
  log "Creating interface endpoint for $svc_short"
  aws ec2 create-vpc-endpoint --region "$REGION" \
    --vpc-id "$VPC_ID" \
    --vpc-endpoint-type Interface \
    --service-name "$svc" \
    --subnet-ids "$APP1" "$APP2" \
    --security-group-ids "$sg_id" \
    --private-dns-enabled \
    --tag-specifications "$(tag_spec vpc-endpoint "$name_tag" "$PREFIX" "$ENVIRONMENT")" \
    >/dev/null
}

create_interface_vpce sqs "$PREFIX-vpce-sqs"
create_interface_vpce secretsmanager "$PREFIX-vpce-secrets"
create_interface_vpce logs "$PREFIX-vpce-logs"
create_interface_vpce ecr.api "$PREFIX-vpce-ecr-api"
create_interface_vpce ecr.dkr "$PREFIX-vpce-ecr-dkr"
create_interface_vpce sts "$PREFIX-vpce-sts"

log "VPC endpoints provisioning requested."
log "Next: ./16-Validate-VpcEndpoints.sh"

