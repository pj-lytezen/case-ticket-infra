#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 16-Validate-VpcEndpoints.sh
#
# Validates VPC endpoints exist and prints their state.
#
# Manual verification (AWS Console):
# - VPC -> Endpoints: confirm endpoints are “Available”
# - Interface endpoints: confirm Private DNS is enabled
# ------------------------------------------------------------

parse_args_prefix_env_region "$@"

require_cmd aws

VPC_ID="$(find_vpc_id_by_name "$REGION" "$PREFIX-vpc")"
[[ -n "$VPC_ID" ]] || die "Missing VPC."

aws ec2 describe-vpc-endpoints --region "$REGION" --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'VpcEndpoints[].{Id:VpcEndpointId,Service:ServiceName,Type:VpcEndpointType,State:State,PrivateDNS:PrivateDnsEnabled}' \
  --output table

