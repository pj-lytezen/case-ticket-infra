#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 07-Create-Storage.sh
#
# Creates S3 buckets for:
# - docs (ingested documents)
# - attachments (customer files)
#
# Idempotency:
# - Bucket names include AWS account id to guarantee global uniqueness.
# - Script checks existence via HeadBucket.
#
# Security baseline:
# - Block all public access
# - Versioning enabled
# - Default encryption enabled (SSE-S3 for simplicity)
# ------------------------------------------------------------

parse_args_prefix_env_region "$@"

require_cmd aws

ACCOUNT_ID="$(aws_account_id "$REGION")"
DOCS_BUCKET="$(printf '%s-%s-docs' "$PREFIX" "$ACCOUNT_ID" | tr '[:upper:]' '[:lower:]')"
ATT_BUCKET="$(printf '%s-%s-attachments' "$PREFIX" "$ACCOUNT_ID" | tr '[:upper:]' '[:lower:]')"

ensure_bucket() {
  local b="$1"
  if aws s3api head-bucket --region "$REGION" --bucket "$b" >/dev/null 2>&1; then
    log "Bucket exists: $b"
  else
    log "Creating bucket: $b"
    if [[ "$REGION" == "us-east-1" ]]; then
      aws s3api create-bucket --region "$REGION" --bucket "$b" >/dev/null
    else
      aws s3api create-bucket --region "$REGION" --bucket "$b" \
        --create-bucket-configuration "LocationConstraint=$REGION" >/dev/null
    fi
  fi

  aws s3api put-public-access-block --region "$REGION" --bucket "$b" \
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true >/dev/null

  aws s3api put-bucket-versioning --region "$REGION" --bucket "$b" \
    --versioning-configuration Status=Enabled >/dev/null

  aws s3api put-bucket-encryption --region "$REGION" --bucket "$b" \
    --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' >/dev/null
}

ensure_bucket "$DOCS_BUCKET"
ensure_bucket "$ATT_BUCKET"

log "Storage complete."
log "Docs bucket       : $DOCS_BUCKET"
log "Attachments bucket: $ATT_BUCKET"
log "Next: ./08-Validate-Storage.sh"

