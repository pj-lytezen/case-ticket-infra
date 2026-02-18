#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 06-Validate-Security.sh (GCP)
#
# Manual verification (GCP Console):
# - Security -> Key Management: confirm key ring and key exist
# - Security -> Secret Manager: confirm secrets exist and have >= 1 version
# ------------------------------------------------------------

parse_args_prefix_project_region_zone "$@"

require_cmd gcloud

gcloud config set project "$PROJECT_ID" >/dev/null

KEYRING="$(to_gc_name "kr-$PREFIX")"
KEY="$(to_gc_name "key-$PREFIX")"
gcloud kms keyrings describe "$KEYRING" --location "$REGION" >/dev/null
gcloud kms keys describe "$KEY" --keyring "$KEYRING" --location "$REGION" >/dev/null
log "KMS OK: $KEYRING/$KEY"

for s in "$(to_gc_name "$PREFIX-sql-password")" "$(to_gc_name "$PREFIX-app-config")"; do
  gcloud secrets describe "$s" >/dev/null
  v="$(gcloud secrets versions list "$s" --format="value(name)" | wc -l | tr -d ' ')"
  log "Secret OK: $s versions=$v"
done

