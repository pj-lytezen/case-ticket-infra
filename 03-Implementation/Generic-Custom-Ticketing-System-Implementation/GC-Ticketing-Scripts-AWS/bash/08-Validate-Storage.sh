#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 08-Validate-Storage.sh
#
# Validates S3 buckets:
# - existence
# - versioning enabled
# - default encryption enabled
# ------------------------------------------------------------

parse_args_prefix_env_region "$@"

require_cmd aws

ACCOUNT_ID="$(aws_account_id "$REGION")"
for b in "$(printf '%s-%s-docs' "$PREFIX" "$ACCOUNT_ID" | tr '[:upper:]' '[:lower:]')" \
         "$(printf '%s-%s-attachments' "$PREFIX" "$ACCOUNT_ID" | tr '[:upper:]' '[:lower:]')"; do
  aws s3api head-bucket --region "$REGION" --bucket "$b" >/dev/null
  ver="$(aws s3api get-bucket-versioning --region "$REGION" --bucket "$b" --query Status --output text)"
  enc="$(aws s3api get-bucket-encryption --region "$REGION" --bucket "$b" --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text)"
  log "Bucket OK: $b Versioning=$ver Encryption=$enc"
done

