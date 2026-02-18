#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 05-Create-Security.sh (GCP)
#
# Creates:
# - Cloud KMS key ring + crypto key
# - Secret Manager secrets (Cloud SQL password, app config)
#
# Idempotency:
# - Key ring / key: created only if missing.
# - Secrets: created only if missing.
# - Secret versions: we add an initial version only if there are zero versions
#   (prevents duplicating versions on re-run).
# ------------------------------------------------------------

parse_args_prefix_project_region_zone "$@"

require_cmd gcloud

gcloud config set project "$PROJECT_ID" >/dev/null

KEYRING="$(to_gc_name "kr-$PREFIX")"
KEY="$(to_gc_name "key-$PREFIX")"

if gcloud kms keyrings describe "$KEYRING" --location "$REGION" >/dev/null 2>&1; then
  log "KMS key ring exists: $KEYRING"
else
  log "Creating KMS key ring: $KEYRING"
  gcloud kms keyrings create "$KEYRING" --location "$REGION" >/dev/null
fi

if gcloud kms keys describe "$KEY" --keyring "$KEYRING" --location "$REGION" >/dev/null 2>&1; then
  log "KMS key exists: $KEY"
else
  log "Creating KMS crypto key: $KEY"
  gcloud kms keys create "$KEY" --keyring "$KEYRING" --location "$REGION" --purpose encryption >/dev/null
fi

random_pw() { LC_ALL=C tr -dc 'A-HJ-NP-Za-km-z2-9' </dev/urandom | head -c 28; }

ensure_secret_with_initial_version() {
  local name="$1" value="$2"
  if gcloud secrets describe "$name" >/dev/null 2>&1; then
    log "Secret exists: $name"
  else
    log "Creating secret: $name"
    gcloud secrets create "$name" --replication-policy=automatic >/dev/null
  fi

  # Add initial version only if none exist.
  versions="$(gcloud secrets versions list "$name" --format="value(name)" | wc -l | tr -d ' ')"
  if [[ "$versions" == "0" ]]; then
    log "Adding initial secret version for: $name"
    tmp="$(mktemp)"
    printf '%s' "$value" >"$tmp"
    gcloud secrets versions add "$name" --data-file="$tmp" >/dev/null
  else
    log "Secret already has versions; not adding a new one (idempotency)."
  fi
}

ensure_secret_with_initial_version "$(to_gc_name "$PREFIX-sql-password")" "$(random_pw)"
ensure_secret_with_initial_version "$(to_gc_name "$PREFIX-app-config")" '{"environment":"prod","notes":"fill after provisioning"}'

log "Security complete."
log "Next: ./06-Validate-Security.sh"

