#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 03-Create-Network.sh (GCP)
#
# Creates network foundation:
# - VPC network (custom mode)
# - Subnet for GKE with secondary ranges (pods/services) for VPC-native GKE
# - Data subnet
# - Firewall rule allowing internal traffic
# - Cloud Router + Cloud NAT (private nodes egress)
#
# Idempotency:
# - Uses describe checks; creates only if missing.
# ------------------------------------------------------------

PREFIX="gc-tkt-prod"
PROJECT_ID=""
REGION="us-central1"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix|-Prefix) PREFIX="$2"; shift 2;;
    --project-id|--ProjectId) PROJECT_ID="$2"; shift 2;;
    --region|-Region) REGION="$2"; shift 2;;
    *) die "Unknown argument: $1";;
  esac
done
[[ -n "$PROJECT_ID" ]] || die "--project-id is required."

require_cmd gcloud

gcloud config set project "$PROJECT_ID" >/dev/null

NET="$(to_gc_name "net-$PREFIX")"
SUB_GKE="$(to_gc_name "subnet-gke-$PREFIX")"
SUB_DATA="$(to_gc_name "subnet-data-$PREFIX")"
ROUTER="$(to_gc_name "cr-$PREFIX")"
NAT="$(to_gc_name "nat-$PREFIX")"
FW_INTERNAL="$(to_gc_name "fw-$PREFIX-allow-internal")"

if gcloud compute networks describe "$NET" >/dev/null 2>&1; then
  log "VPC exists: $NET"
else
  log "Creating VPC network: $NET"
  gcloud compute networks create "$NET" --subnet-mode=custom >/dev/null
fi

if gcloud compute networks subnets describe "$SUB_GKE" --region "$REGION" >/dev/null 2>&1; then
  log "Subnet exists: $SUB_GKE"
else
  log "Creating subnet: $SUB_GKE (with secondary ranges for GKE)"
  gcloud compute networks subnets create "$SUB_GKE" --region "$REGION" --network "$NET" \
    --range 10.20.20.0/22 \
    --secondary-range "pods=10.60.0.0/16,services=10.70.0.0/20" >/dev/null
fi

if gcloud compute networks subnets describe "$SUB_DATA" --region "$REGION" >/dev/null 2>&1; then
  log "Subnet exists: $SUB_DATA"
else
  log "Creating subnet: $SUB_DATA"
  gcloud compute networks subnets create "$SUB_DATA" --region "$REGION" --network "$NET" \
    --range 10.20.30.0/24 >/dev/null
fi

if gcloud compute firewall-rules describe "$FW_INTERNAL" >/dev/null 2>&1; then
  log "Firewall rule exists: $FW_INTERNAL"
else
  log "Creating firewall rule: $FW_INTERNAL"
  gcloud compute firewall-rules create "$FW_INTERNAL" --network "$NET" \
    --allow tcp,udp,icmp \
    --source-ranges 10.20.0.0/16,10.60.0.0/16,10.70.0.0/20 \
    --description "Allow internal VPC + GKE secondary ranges" >/dev/null
fi

if gcloud compute routers describe "$ROUTER" --region "$REGION" >/dev/null 2>&1; then
  log "Router exists: $ROUTER"
else
  log "Creating Cloud Router: $ROUTER"
  gcloud compute routers create "$ROUTER" --region "$REGION" --network "$NET" >/dev/null
fi

if gcloud compute routers nats describe "$NAT" --router "$ROUTER" --region "$REGION" >/dev/null 2>&1; then
  log "NAT exists: $NAT"
else
  log "Creating Cloud NAT: $NAT"
  gcloud compute routers nats create "$NAT" --router "$ROUTER" --region "$REGION" \
    --nat-all-subnet-ip-ranges \
    --auto-allocate-nat-external-ips >/dev/null
fi

log "Network foundation complete."
log "Next: ./04-Validate-Network.sh"

