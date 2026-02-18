#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 05-Create-Security.sh
#
# Creates security primitives:
# - KMS key + alias (alias/<prefix>-kms) used for encryption at rest patterns
# - Secrets Manager secrets (RDS master creds + placeholder app config)
#
# Idempotency:
# - KMS: if alias exists, reuse its key
# - Secrets: if secret exists, do not overwrite by default
# ------------------------------------------------------------

parse_args_prefix_env_region "$@"

require_cmd aws
require_cmd jq

KMS_ALIAS="alias/$PREFIX-kms"
TARGET_KEY_ID="$(aws kms list-aliases --region "$REGION" --query "Aliases[?AliasName=='$KMS_ALIAS'].TargetKeyId | [0]" --output text)"
TARGET_KEY_ID="$(none_to_empty "$TARGET_KEY_ID")"

if [[ -n "$TARGET_KEY_ID" ]]; then
  log "KMS alias exists: $KMS_ALIAS -> $TARGET_KEY_ID"
  KMS_KEY_ID="$TARGET_KEY_ID"
else
  log "Creating KMS key for $KMS_ALIAS"
  KMS_KEY_ID="$(aws kms create-key --region "$REGION" \
    --description "$PREFIX key for GC Ticketing" \
    --key-usage ENCRYPT_DECRYPT \
    --origin AWS_KMS \
    --query 'KeyMetadata.KeyId' --output text)"

  # Enable annual rotation as a baseline best practice.
  aws kms enable-key-rotation --region "$REGION" --key-id "$KMS_KEY_ID" >/dev/null
  aws kms create-alias --region "$REGION" --alias-name "$KMS_ALIAS" --target-key-id "$KMS_KEY_ID" >/dev/null
  log "Created KMS key: $KMS_KEY_ID"
fi

ensure_secret() {
  local name="$1" description="$2" secret_json="$3"
  if aws secretsmanager describe-secret --region "$REGION" --secret-id "$name" >/dev/null 2>&1; then
    log "Secret exists: $name"
    return
  fi
  log "Creating secret: $name"
  aws secretsmanager create-secret --region "$REGION" \
    --name "$name" \
    --description "$description" \
    --secret-string "$secret_json" >/dev/null
}

# RDS master secret (referenced by the RDS creation script).
DB_USER="gc_admin"
DB_PASS="$(random_password 28)"
DB_SECRET_NAME="$PREFIX/rds/master"
DB_SECRET_JSON="$(jq -cn --arg u "$DB_USER" --arg p "$DB_PASS" '{username:$u,password:$p,engine:"postgres"}')"
ensure_secret "$DB_SECRET_NAME" "Master credentials for $PREFIX RDS Postgres" "$DB_SECRET_JSON"

# Placeholder app config secret.
APP_SECRET_NAME="$PREFIX/app/config"
APP_SECRET_JSON="$(jq -cn --arg env "$ENVIRONMENT" '{environment:$env}')"
ensure_secret "$APP_SECRET_NAME" "Application config for $PREFIX" "$APP_SECRET_JSON"

log "Security primitives complete."
log "Next: ./06-Validate-Security.sh"

