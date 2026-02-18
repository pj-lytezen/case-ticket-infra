#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 01-Context.sh (GCP)
#
# Purpose:
# - Pre-flight checks: confirm gcloud is installed and authenticated.
# - Set active project/region/zone to avoid deploying to the wrong project.
# - Enable required APIs up front (idempotent and prevents later failures).
# ------------------------------------------------------------

parse_args_prefix_project_region_zone "$@"

require_cmd gcloud

log "Prefix=$PREFIX ProjectId=$PROJECT_ID Region=$REGION Zone=$ZONE"

gcloud config set project "$PROJECT_ID" >/dev/null
gcloud config set compute/region "$REGION" >/dev/null
gcloud config set compute/zone "$ZONE" >/dev/null

active_acct="$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | tr -d '\r')"
log "Active account: $active_acct"

# APIs required by the design.
apis=(
  compute.googleapis.com
  container.googleapis.com
  sqladmin.googleapis.com
  servicenetworking.googleapis.com
  secretmanager.googleapis.com
  cloudkms.googleapis.com
  pubsub.googleapis.com
  logging.googleapis.com
  monitoring.googleapis.com
  artifactregistry.googleapis.com
)

log "Enabling required APIs (safe to re-run)..."
gcloud services enable "${apis[@]}" >/dev/null

log "Context OK. Next: ./03-Create-Network.sh"

