#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 04-Validate-Network.sh
#
# Validates the network created by 03-Create-Network.sh.
#
# Manual verification (AWS Console):
# - VPC -> Your VPCs: confirm VPC exists and DNS is enabled
# - VPC -> Subnets: confirm 2 public, 2 app-private, 2 data-private subnets
# - VPC -> NAT Gateways: confirm NATs are “Available”
# - VPC -> Route Tables: confirm private routes point to NATs and public routes point to IGW
# ------------------------------------------------------------

parse_args_prefix_env_region "$@"

require_cmd aws

VPC_ID="$(find_vpc_id_by_name "$REGION" "$PREFIX-vpc")"
[[ -n "$VPC_ID" ]] || die "Missing VPC with Name tag '$PREFIX-vpc'. Run ./03-Create-Network.sh."

log "VPC: $VPC_ID"
aws ec2 describe-subnets --region "$REGION" --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[].{SubnetId:SubnetId,AZ:AvailabilityZone,CIDR:CidrBlock,Name:Tags[?Key==`Name`]|[0].Value}' \
  --output table

IGW_ID="$(aws ec2 describe-internet-gateways --region "$REGION" --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
  --query 'InternetGateways[0].InternetGatewayId' --output text)"
log "IGW attached: $IGW_ID"

aws ec2 describe-nat-gateways --region "$REGION" --filter "Name=vpc-id,Values=$VPC_ID" \
  --query 'NatGateways[].{Id:NatGatewayId,State:State,Subnet:SubnetId}' --output table

aws ec2 describe-route-tables --region "$REGION" --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'RouteTables[].{Id:RouteTableId,Name:Tags[?Key==`Name`]|[0].Value}' --output table

