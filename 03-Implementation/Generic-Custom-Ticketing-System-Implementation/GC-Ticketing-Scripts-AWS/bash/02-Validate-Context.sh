#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 02-Validate-Context.sh
#
# Validation companion for 01-Context.sh.
#
# Manual verification (AWS Console):
# - IAM permissions: confirm principal can create VPC/EKS/RDS/S3/SQS/KMS/VPCE.
# - Billing -> Cost allocation tags: optionally activate Project/Environment tags.
# ------------------------------------------------------------

parse_args_prefix_env_region "$@"

require_cmd aws
require_cmd jq

acct_json="$(aws sts get-caller-identity --region "$REGION" --output json)"
log "OK: Authenticated as $(jq -r '.Arn' <<<"$acct_json") in account $(jq -r '.Account' <<<"$acct_json") region $REGION"
log "Reminder: verify account/region before provisioning production resources."

