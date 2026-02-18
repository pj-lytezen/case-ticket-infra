#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 02-Validate-Context.sh (GCP)
#
# Manual verification (GCP Console):
# - Confirm correct project in project picker
# - APIs & Services -> Enabled APIs: confirm Compute, GKE, Cloud SQL, Secret Manager, KMS, Pub/Sub
# ------------------------------------------------------------

parse_args_prefix_project_region_zone "$@"

require_cmd gcloud

gcloud projects describe "$PROJECT_ID" --format="json(projectId,projectNumber)" | sed 's/^/  /'
enabled_count="$(gcloud services list --enabled --format="value(config.name)" | wc -l | tr -d ' ')"
log "Enabled services count: $enabled_count"

