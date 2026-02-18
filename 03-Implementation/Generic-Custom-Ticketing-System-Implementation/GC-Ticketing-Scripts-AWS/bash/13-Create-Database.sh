#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 13-Create-Database.sh
#
# Creates RDS PostgreSQL (Multi-AZ) for:
# - sessions/messages/events
# - tickets/comments
# - Hybrid RAG indices (FTS + pgvector)
# - outbox table
#
# Idempotency:
# - Reuses subnet group, SG, and DB instance if present.
#
# Security note:
# - For initial deployment we allow DB access from VPC CIDR (simple).
# - Harden later by allowing only EKS node security groups.
# ------------------------------------------------------------

PREFIX="gc-tkt-prod"
ENVIRONMENT="prod"
REGION="us-east-1"
DB_CLASS="db.t4g.medium"
STORAGE_GB=200
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix|-Prefix) PREFIX="$2"; shift 2;;
    --environment|--env) ENVIRONMENT="$2"; shift 2;;
    --region|-Region) REGION="$2"; shift 2;;
    --db-instance-class|--DbInstanceClass) DB_CLASS="$2"; shift 2;;
    --storage-gb|--AllocatedStorageGb) STORAGE_GB="$2"; shift 2;;
    *) die "Unknown argument: $1";;
  esac
done

require_cmd aws
require_cmd jq

read -r AZ1 AZ2 <<<"$(get_two_azs "$REGION")"
VPC_ID="$(find_vpc_id_by_name "$REGION" "$PREFIX-vpc")"
[[ -n "$VPC_ID" ]] || die "Missing VPC. Run ./03-Create-Network.sh."

DATA1="$(find_subnet_id_by_name "$REGION" "$VPC_ID" "$PREFIX-data-$AZ1")"
DATA2="$(find_subnet_id_by_name "$REGION" "$VPC_ID" "$PREFIX-data-$AZ2")"
[[ -n "$DATA1" && -n "$DATA2" ]] || die "Missing data subnets. Run ./03-Create-Network.sh."

SUBNET_GROUP="$PREFIX-db-subnets"
if aws rds describe-db-subnet-groups --region "$REGION" --db-subnet-group-name "$SUBNET_GROUP" >/dev/null 2>&1; then
  log "DB subnet group exists: $SUBNET_GROUP"
else
  log "Creating DB subnet group: $SUBNET_GROUP"
  aws rds create-db-subnet-group --region "$REGION" \
    --db-subnet-group-name "$SUBNET_GROUP" \
    --db-subnet-group-description "$PREFIX DB subnet group" \
    --subnet-ids "$DATA1" "$DATA2" >/dev/null
fi

DB_SG_NAME="$PREFIX-db-sg"
DB_SG_ID="$(find_sg_id_by_group_name "$REGION" "$VPC_ID" "$DB_SG_NAME")"
if [[ -z "$DB_SG_ID" ]]; then
  log "Creating DB security group: $DB_SG_NAME"
  DB_SG_ID="$(aws ec2 create-security-group --region "$REGION" --vpc-id "$VPC_ID" \
    --group-name "$DB_SG_NAME" --description "$PREFIX RDS Postgres SG" \
    --query GroupId --output text)"
  aws ec2 create-tags --region "$REGION" --resources "$DB_SG_ID" --tags \
    "Key=Name,Value=$DB_SG_NAME" $(default_tags_kv "$PREFIX" "$ENVIRONMENT") >/dev/null

  VPC_CIDR="$(aws ec2 describe-vpcs --region "$REGION" --vpc-ids "$VPC_ID" --query 'Vpcs[0].CidrBlock' --output text)"
  aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$DB_SG_ID" \
    --ip-permissions "IpProtocol=tcp,FromPort=5432,ToPort=5432,IpRanges=[{CidrIp=$VPC_CIDR,Description=VPC-internal}]" \
    >/dev/null 2>&1 || true
else
  log "DB security group exists: $DB_SG_NAME ($DB_SG_ID)"
fi

# Read master credentials from Secrets Manager.
SECRET_NAME="$PREFIX/rds/master"
SECRET_STR="$(aws secretsmanager get-secret-value --region "$REGION" --secret-id "$SECRET_NAME" --query SecretString --output text)"
DB_USER="$(jq -r '.username' <<<"$SECRET_STR")"
DB_PASS="$(jq -r '.password' <<<"$SECRET_STR")"

DB_ID="$PREFIX-pg"
if aws rds describe-db-instances --region "$REGION" --db-instance-identifier "$DB_ID" >/dev/null 2>&1; then
  status="$(aws rds describe-db-instances --region "$REGION" --db-instance-identifier "$DB_ID" --query 'DBInstances[0].DBInstanceStatus' --output text)"
  log "RDS instance exists: $DB_ID status=$status"
else
  log "Creating RDS PostgreSQL instance: $DB_ID (Multi-AZ)"
  aws rds create-db-instance --region "$REGION" \
    --db-instance-identifier "$DB_ID" \
    --engine postgres \
    --db-instance-class "$DB_CLASS" \
    --allocated-storage "$STORAGE_GB" \
    --multi-az \
    --storage-type gp3 \
    --db-subnet-group-name "$SUBNET_GROUP" \
    --vpc-security-group-ids "$DB_SG_ID" \
    --master-username "$DB_USER" \
    --master-user-password "$DB_PASS" \
    --backup-retention-period 7 \
    --no-publicly-accessible \
    --deletion-protection \
    --tags "Key=Project,Value=SupportTicketAutomation" "Key=Environment,Value=$ENVIRONMENT" "Key=Prefix,Value=$PREFIX" "Key=Name,Value=$DB_ID" \
    >/dev/null
fi

log "Waiting for DB to become AVAILABLE (can take 15–45 minutes)..."
aws rds wait db-instance-available --region "$REGION" --db-instance-identifier "$DB_ID"

endpoint="$(aws rds describe-db-instances --region "$REGION" --db-instance-identifier "$DB_ID" --query 'DBInstances[0].Endpoint.Address' --output text)"
port="$(aws rds describe-db-instances --region "$REGION" --db-instance-identifier "$DB_ID" --query 'DBInstances[0].Endpoint.Port' --output text)"
log "RDS available: $endpoint:$port"
log "Next: ./14-Validate-Database.sh"

