#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 07-Create-Storage.sh (GCP)
#
# Creates Cloud Storage buckets for:
# - documents
# - attachments
#
# Idempotency:
# - Bucket names are global; include project id to reduce collisions.
# - If bucket exists, script enforces security settings.
#
# Security baseline:
# - Uniform bucket-level access
# - Public access prevention enforced
# ------------------------------------------------------------

parse_args_prefix_project_region_zone "$@"

require_cmd gcloud

gcloud config set project "$PROJECT_ID" >/dev/null

ensure_bucket() {
  local name="$1"
  if gcloud storage buckets describe "gs://$name" >/dev/null 2>&1; then
    log "Bucket exists: $name"
  else
    log "Creating bucket: $name"
    gcloud storage buckets create "gs://$name" --location="$REGION" --uniform-bucket-level-access >/dev/null
  fi
  gcloud storage buckets update "gs://$name" --public-access-prevention=enforced >/dev/null
}

DOCS="$(to_gc_name "$PREFIX-$PROJECT_ID-docs")"
ATTS="$(to_gc_name "$PREFIX-$PROJECT_ID-attachments")"

ensure_bucket "$DOCS"
ensure_bucket "$ATTS"

log "Storage complete."
log "Docs bucket       : gs://$DOCS"
log "Attachments bucket: gs://$ATTS"
log "Next: ./08-Validate-Storage.sh"

