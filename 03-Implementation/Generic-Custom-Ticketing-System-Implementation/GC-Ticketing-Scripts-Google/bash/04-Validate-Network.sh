#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 04-Validate-Network.sh (GCP)
#
# Manual verification (GCP Console):
# - VPC networks: confirm net-<prefix> exists
# - Subnets: confirm subnet-gke and subnet-data exist with correct ranges
# - Cloud NAT: confirm NAT is configured and attached to Cloud Router
# ------------------------------------------------------------

parse_args_prefix_project_region_zone "$@"

require_cmd gcloud

gcloud config set project "$PROJECT_ID" >/dev/null

NET="$(to_gc_name "net-$PREFIX")"
SUB_GKE="$(to_gc_name "subnet-gke-$PREFIX")"
SUB_DATA="$(to_gc_name "subnet-data-$PREFIX")"
ROUTER="$(to_gc_name "cr-$PREFIX")"
NAT="$(to_gc_name "nat-$PREFIX")"

gcloud compute networks describe "$NET" --format="yaml(name)" | sed 's/^/  /'
gcloud compute networks subnets describe "$SUB_GKE" --region "$REGION" --format="yaml(name,ipCidrRange,secondaryIpRanges)" | sed 's/^/  /'
gcloud compute networks subnets describe "$SUB_DATA" --region "$REGION" --format="yaml(name,ipCidrRange)" | sed 's/^/  /'
gcloud compute routers describe "$ROUTER" --region "$REGION" --format="yaml(name,network)" | sed 's/^/  /'
gcloud compute routers nats describe "$NAT" --router "$ROUTER" --region "$REGION" --format="yaml(name,natIpAllocateOption,sourceSubnetworkIpRangesToNat)" | sed 's/^/  /'

