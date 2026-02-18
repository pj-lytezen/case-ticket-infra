#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 06-Validate-Security.sh
#
# Validates:
# - KMS alias exists and points to a key
# - Required secrets exist
#
# Manual verification (AWS Console):
# - KMS -> Customer managed keys: confirm alias/<prefix>-kms exists and rotation is enabled
# - Secrets Manager -> Secrets: confirm <prefix>/rds/master and <prefix>/app/config exist
# ------------------------------------------------------------

parse_args_prefix_env_region "$@"

require_cmd aws

KMS_ALIAS="alias/$PREFIX-kms"
KEY_ID="$(aws kms list-aliases --region "$REGION" --query "Aliases[?AliasName=='$KMS_ALIAS'].TargetKeyId | [0]" --output text)"
KEY_ID="$(none_to_empty "$KEY_ID")"
[[ -n "$KEY_ID" ]] || die "Missing KMS alias: $KMS_ALIAS"
log "KMS alias OK: $KMS_ALIAS -> $KEY_ID"

for s in "$PREFIX/rds/master" "$PREFIX/app/config"; do
  aws secretsmanager describe-secret --region "$REGION" --secret-id "$s" >/dev/null
  log "Secret OK: $s"
done

