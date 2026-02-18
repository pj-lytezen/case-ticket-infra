#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 14-Validate-Database.sh
#
# Validates RDS instance properties.
#
# Manual verification (AWS Console):
# - RDS -> Databases: confirm <prefix>-pg is Available, Multi-AZ=Yes, Public access=No
# - VPC security groups: confirm inbound is limited (tighten to EKS SGs later)
# ------------------------------------------------------------

parse_args_prefix_env_region "$@"

require_cmd aws

DB_ID="$PREFIX-pg"
aws rds describe-db-instances --region "$REGION" --db-instance-identifier "$DB_ID" \
  --query 'DBInstances[0].{id:DBInstanceIdentifier,status:DBInstanceStatus,engine:Engine,class:DBInstanceClass,multiAZ:MultiAZ,public:PubliclyAccessible,endpoint:Endpoint.Address,port:Endpoint.Port,subnetGroup:DBSubnetGroup.DBSubnetGroupName}' \
  --output table

