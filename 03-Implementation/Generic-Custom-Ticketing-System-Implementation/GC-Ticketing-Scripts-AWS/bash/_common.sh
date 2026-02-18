#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# Common helpers for AWS bash provisioning scripts
#
# Why this file exists:
# - Centralizes idempotent lookup logic (find by tag/name).
# - Keeps scripts readable and consistent.
# - Avoids subtle quoting bugs scattered across many scripts.
#
# Usage in a script:
#   source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
# -------------------------------------------------------------------

log() { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found on PATH."
}

# Normalize AWS CLI "None" output to empty.
none_to_empty() {
  local v="${1:-}"
  if [[ "$v" == "None" || "$v" == "null" ]]; then
    printf ''
  else
    printf '%s' "$v"
  fi
}

aws_account_id() {
  local region="$1"
  aws sts get-caller-identity --region "$region" --query Account --output text
}

get_two_azs() {
  # Returns 2 AZ names as "az1 az2"
  local region="$1"
  local azs
  azs="$(aws ec2 describe-availability-zones \
    --region "$region" \
    --filters "Name=region-name,Values=$region" "Name=state,Values=available" \
    --query 'AvailabilityZones[].ZoneName' --output text)"
  # shellcheck disable=SC2206
  local arr=($azs)
  [[ "${#arr[@]}" -ge 2 ]] || die "Region '$region' has fewer than 2 available AZs."
  printf '%s %s' "${arr[0]}" "${arr[1]}"
}

default_tags_kv() {
  # Emits key/value tag pairs as "Key=...,Value=..." fragments suitable for `aws ec2 create-tags`.
  local prefix="$1"
  local env="$2"
  printf 'Key=Project,Value=SupportTicketAutomation Key=Environment,Value=%s Key=Owner,Value=%s Key=Prefix,Value=%s' \
    "$env" "${USER:-unknown}" "$prefix"
}

tag_spec() {
  # Creates an AWS `--tag-specifications` string for a given resource type and Name tag.
  #
  # Example output:
  #   ResourceType=vpc,Tags=[{Key=Name,Value=...},{Key=Project,Value=...},...]
  local resource_type="$1"
  local name_value="$2"
  local prefix="$3"
  local env="$4"
  printf 'ResourceType=%s,Tags=[{Key=Name,Value=%s},{Key=Project,Value=SupportTicketAutomation},{Key=Environment,Value=%s},{Key=Owner,Value=%s},{Key=Prefix,Value=%s}]' \
    "$resource_type" "$name_value" "$env" "${USER:-unknown}" "$prefix"
}

find_vpc_id_by_name() {
  local region="$1"
  local name="$2"
  local id
  id="$(aws ec2 describe-vpcs --region "$region" \
    --filters "Name=tag:Name,Values=$name" \
    --query 'Vpcs[0].VpcId' --output text)"
  none_to_empty "$id"
}

find_subnet_id_by_name() {
  local region="$1"
  local vpc_id="$2"
  local name="$3"
  local id
  id="$(aws ec2 describe-subnets --region "$region" \
    --filters "Name=vpc-id,Values=$vpc_id" "Name=tag:Name,Values=$name" \
    --query 'Subnets[0].SubnetId' --output text)"
  none_to_empty "$id"
}

find_igw_id_by_name() {
  local region="$1"
  local name="$2"
  local id
  id="$(aws ec2 describe-internet-gateways --region "$region" \
    --filters "Name=tag:Name,Values=$name" \
    --query 'InternetGateways[0].InternetGatewayId' --output text)"
  none_to_empty "$id"
}

find_route_table_id_by_name() {
  local region="$1"
  local vpc_id="$2"
  local name="$3"
  local id
  id="$(aws ec2 describe-route-tables --region "$region" \
    --filters "Name=vpc-id,Values=$vpc_id" "Name=tag:Name,Values=$name" \
    --query 'RouteTables[0].RouteTableId' --output text)"
  none_to_empty "$id"
}

find_sg_id_by_group_name() {
  local region="$1"
  local vpc_id="$2"
  local group_name="$3"
  local id
  id="$(aws ec2 describe-security-groups --region "$region" \
    --filters "Name=vpc-id,Values=$vpc_id" "Name=group-name,Values=$group_name" \
    --query 'SecurityGroups[0].GroupId' --output text)"
  none_to_empty "$id"
}

random_password() {
  # Generates a password without special characters to avoid CLI quoting issues.
  # Increase complexity later if desired.
  local len="${1:-28}"
  LC_ALL=C tr -dc 'A-HJ-NP-Za-km-z2-9' </dev/urandom | head -c "$len"
}

parse_args_prefix_env_region() {
  # Convenience parser for the majority of scripts.
  # Sets global vars: PREFIX, ENVIRONMENT, REGION.
  PREFIX="gc-tkt-prod"
  ENVIRONMENT="prod"
  REGION="us-east-1"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --prefix|-prefix|-Prefix) PREFIX="$2"; shift 2;;
      --environment|--env|-env|-Environment) ENVIRONMENT="$2"; shift 2;;
      --region|-region|-Region) REGION="$2"; shift 2;;
      *) die "Unknown argument: $1";;
    esac
  done
}

