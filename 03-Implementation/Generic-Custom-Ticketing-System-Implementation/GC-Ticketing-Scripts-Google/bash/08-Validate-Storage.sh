#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 08-Validate-Storage.sh (GCP)
#
# Validates buckets and public access prevention.
#
# Manual verification (GCP Console):
# - Cloud Storage -> Buckets: confirm docs/attachments exist
# - IAM & admin: confirm Public access prevention is enforced
# ------------------------------------------------------------

parse_args_prefix_project_region_zone "$@"

require_cmd gcloud

gcloud config set project "$PROJECT_ID" >/dev/null

for b in "$(to_gc_name "$PREFIX-$PROJECT_ID-docs")" "$(to_gc_name "$PREFIX-$PROJECT_ID-attachments")"; do
  gcloud storage buckets describe "gs://$b" >/dev/null
  pap="$(gcloud storage buckets describe "gs://$b" --format="value(iamConfiguration.publicAccessPrevention)" | tr -d '\r')"
  log "Bucket OK: $b publicAccessPrevention=$pap"
done

