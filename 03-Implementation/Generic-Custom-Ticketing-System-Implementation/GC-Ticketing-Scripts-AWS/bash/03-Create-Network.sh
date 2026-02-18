#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 03-Create-Network.sh
#
# Creates the AWS network foundation:
# - VPC with DNS enabled
# - 2 public subnets (for IGW/NAT/ingress)
# - 2 private app subnets (EKS nodes/services)
# - 2 private data subnets (RDS)
# - Internet Gateway
# - Route tables (public + per-AZ private)
# - 2 NAT Gateways (one per AZ) for private subnet egress
#
# Why:
# - Mirrors the design’s “private-by-default” posture.
# - Uses 2 AZs for HA while limiting NAT cost.
#
# Idempotency:
# - Finds resources by Name tag and reuses them.
# ------------------------------------------------------------

PREFIX="gc-tkt-prod"
ENVIRONMENT="prod"
REGION="us-east-1"
VPC_CIDR="10.20.0.0/16"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix|-Prefix|-prefix) PREFIX="$2"; shift 2;;
    --environment|--env) ENVIRONMENT="$2"; shift 2;;
    --region|-Region|-region) REGION="$2"; shift 2;;
    --vpc-cidr|--VpcCidr) VPC_CIDR="$2"; shift 2;;
    *) die "Unknown argument: $1";;
  esac
done

require_cmd aws

read -r AZ1 AZ2 <<<"$(get_two_azs "$REGION")"

VPC_NAME="$PREFIX-vpc"
VPC_ID="$(find_vpc_id_by_name "$REGION" "$VPC_NAME")"
if [[ -z "$VPC_ID" ]]; then
  log "Creating VPC $VPC_NAME ($VPC_CIDR)"
  aws ec2 create-vpc --region "$REGION" \
    --cidr-block "$VPC_CIDR" \
    --tag-specifications "$(tag_spec vpc "$VPC_NAME" "$PREFIX" "$ENVIRONMENT")" \
    --output json >/dev/null
  VPC_ID="$(find_vpc_id_by_name "$REGION" "$VPC_NAME")"

  # Enable DNS for private service discovery (EKS endpoints, VPCE private DNS, etc.).
  aws ec2 modify-vpc-attribute --region "$REGION" --vpc-id "$VPC_ID" --enable-dns-support '{"Value":true}' >/dev/null
  aws ec2 modify-vpc-attribute --region "$REGION" --vpc-id "$VPC_ID" --enable-dns-hostnames '{"Value":true}' >/dev/null
else
  log "VPC exists: $VPC_ID"
fi

ensure_subnet() {
  local name="$1" cidr="$2" az="$3" map_public="$4"
  local id
  id="$(find_subnet_id_by_name "$REGION" "$VPC_ID" "$name")"
  if [[ -n "$id" ]]; then
    log "Subnet exists: $name ($id)"
    printf '%s' "$id"
    return
  fi
  log "Creating subnet $name ($cidr) in $az"
  id="$(aws ec2 create-subnet --region "$REGION" \
    --vpc-id "$VPC_ID" \
    --cidr-block "$cidr" \
    --availability-zone "$az" \
    --tag-specifications "$(tag_spec subnet "$name" "$PREFIX" "$ENVIRONMENT")" \
    --query 'Subnet.SubnetId' --output text)"
  aws ec2 modify-subnet-attribute --region "$REGION" --subnet-id "$id" \
    --map-public-ip-on-launch "{\"Value\":$map_public}" >/dev/null
  printf '%s' "$id"
}

# CIDR plan: deterministic blocks for repeatability.
PUB1="$(ensure_subnet "$PREFIX-public-$AZ1" "10.20.0.0/20"   "$AZ1" true)"
PUB2="$(ensure_subnet "$PREFIX-public-$AZ2" "10.20.16.0/20"  "$AZ2" true)"
APP1="$(ensure_subnet "$PREFIX-app-$AZ1"    "10.20.128.0/20" "$AZ1" false)"
APP2="$(ensure_subnet "$PREFIX-app-$AZ2"    "10.20.144.0/20" "$AZ2" false)"
DATA1="$(ensure_subnet "$PREFIX-data-$AZ1"  "10.20.192.0/20" "$AZ1" false)"
DATA2="$(ensure_subnet "$PREFIX-data-$AZ2"  "10.20.208.0/20" "$AZ2" false)"

# Internet Gateway
IGW_NAME="$PREFIX-igw"
IGW_ID="$(find_igw_id_by_name "$REGION" "$IGW_NAME")"
if [[ -z "$IGW_ID" ]]; then
  log "Creating Internet Gateway $IGW_NAME"
  IGW_ID="$(aws ec2 create-internet-gateway --region "$REGION" \
    --tag-specifications "$(tag_spec internet-gateway "$IGW_NAME" "$PREFIX" "$ENVIRONMENT")" \
    --query 'InternetGateway.InternetGatewayId' --output text)"
  aws ec2 attach-internet-gateway --region "$REGION" --vpc-id "$VPC_ID" --internet-gateway-id "$IGW_ID" >/dev/null
else
  log "Internet Gateway exists: $IGW_ID"
fi

ensure_route_table() {
  local name="$1"
  local id
  id="$(find_route_table_id_by_name "$REGION" "$VPC_ID" "$name")"
  if [[ -n "$id" ]]; then
    printf '%s' "$id"
    return
  fi
  log "Creating route table $name"
  aws ec2 create-route-table --region "$REGION" --vpc-id "$VPC_ID" \
    --tag-specifications "$(tag_spec route-table "$name" "$PREFIX" "$ENVIRONMENT")" \
    --query 'RouteTable.RouteTableId' --output text
}

ensure_route() {
  local rt_id="$1" dst="$2" target_arg="$3" target_val="$4"
  local exists
  exists="$(aws ec2 describe-route-tables --region "$REGION" --route-table-ids "$rt_id" \
    --query "RouteTables[0].Routes[?DestinationCidrBlock=='$dst' && State!='blackhole'] | length(@)" --output text)"
  if [[ "$exists" != "0" ]]; then
    log "Route exists: $rt_id -> $dst"
    return
  fi
  log "Creating route: $rt_id -> $dst ($target_arg=$target_val)"
  aws ec2 create-route --region "$REGION" --route-table-id "$rt_id" \
    --destination-cidr-block "$dst" "$target_arg" "$target_val" >/dev/null
}

ensure_rt_assoc() {
  local rt_id="$1" subnet_id="$2"
  local exists
  exists="$(aws ec2 describe-route-tables --region "$REGION" --route-table-ids "$rt_id" \
    --query "RouteTables[0].Associations[?SubnetId=='$subnet_id'] | length(@)" --output text)"
  if [[ "$exists" != "0" ]]; then
    log "Association exists: $rt_id <-> $subnet_id"
    return
  fi
  log "Associating subnet $subnet_id to route table $rt_id"
  aws ec2 associate-route-table --region "$REGION" --route-table-id "$rt_id" --subnet-id "$subnet_id" >/dev/null
}

RT_PUBLIC="$(ensure_route_table "$PREFIX-rt-public")"
ensure_route "$RT_PUBLIC" "0.0.0.0/0" --gateway-id "$IGW_ID"
ensure_rt_assoc "$RT_PUBLIC" "$PUB1"
ensure_rt_assoc "$RT_PUBLIC" "$PUB2"

ensure_eip() {
  local name="$1"
  local alloc
  alloc="$(aws ec2 describe-addresses --region "$REGION" --filters "Name=tag:Name,Values=$name" \
    --query 'Addresses[0].AllocationId' --output text)"
  alloc="$(none_to_empty "$alloc")"
  if [[ -n "$alloc" ]]; then
    log "EIP exists: $name ($alloc)"
    printf '%s' "$alloc"
    return
  fi
  log "Allocating EIP for NAT: $name"
  alloc="$(aws ec2 allocate-address --region "$REGION" --domain vpc --query AllocationId --output text)"
  aws ec2 create-tags --region "$REGION" --resources "$alloc" --tags \
    "Key=Name,Value=$name" $(default_tags_kv "$PREFIX" "$ENVIRONMENT") >/dev/null
  printf '%s' "$alloc"
}

ensure_nat() {
  local name="$1" public_subnet="$2" allocation_id="$3"
  local id
  id="$(aws ec2 describe-nat-gateways --region "$REGION" \
    --filter "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=$name" \
    --query "NatGateways[?State!='deleted'][0].NatGatewayId" --output text)"
  id="$(none_to_empty "$id")"
  if [[ -n "$id" ]]; then
    local state
    state="$(aws ec2 describe-nat-gateways --region "$REGION" --nat-gateway-ids "$id" \
      --query 'NatGateways[0].State' --output text)"
    log "NAT Gateway exists: $name ($id) state=$state"
    printf '%s' "$id"
    return
  fi
  log "Creating NAT Gateway $name in subnet $public_subnet"
  aws ec2 create-nat-gateway --region "$REGION" \
    --subnet-id "$public_subnet" \
    --allocation-id "$allocation_id" \
    --tag-specifications "$(tag_spec natgateway "$name" "$PREFIX" "$ENVIRONMENT")" \
    --query 'NatGateway.NatGatewayId' --output text
}

EIP1="$(ensure_eip "$PREFIX-eip-nat-$AZ1")"
EIP2="$(ensure_eip "$PREFIX-eip-nat-$AZ2")"
NAT1="$(ensure_nat "$PREFIX-nat-$AZ1" "$PUB1" "$EIP1")"
NAT2="$(ensure_nat "$PREFIX-nat-$AZ2" "$PUB2" "$EIP2")"

log "Waiting for NAT gateways to become available (this can take several minutes)..."
aws ec2 wait nat-gateway-available --region "$REGION" --nat-gateway-ids "$NAT1" "$NAT2"

RT_PRIV1="$(ensure_route_table "$PREFIX-rt-private-$AZ1")"
RT_PRIV2="$(ensure_route_table "$PREFIX-rt-private-$AZ2")"
ensure_route "$RT_PRIV1" "0.0.0.0/0" --nat-gateway-id "$NAT1"
ensure_route "$RT_PRIV2" "0.0.0.0/0" --nat-gateway-id "$NAT2"

ensure_rt_assoc "$RT_PRIV1" "$APP1"
ensure_rt_assoc "$RT_PRIV2" "$APP2"
ensure_rt_assoc "$RT_PRIV1" "$DATA1"
ensure_rt_assoc "$RT_PRIV2" "$DATA2"

log "Network foundation complete."
log "Next: ./04-Validate-Network.sh"

