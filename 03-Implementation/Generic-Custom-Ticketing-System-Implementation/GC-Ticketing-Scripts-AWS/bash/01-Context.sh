#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 01-Context.sh
#
# Purpose:
# - Pre-flight check: ensure required local tools exist.
# - Confirm AWS identity (account + principal ARN).
# - Confirm region has >= 2 AZs (required for HA network/EKS/RDS).
#
# Idempotency:
# - No resources created. Safe to run any time.
# ------------------------------------------------------------

parse_args_prefix_env_region "$@"

require_cmd aws
require_cmd jq

log "Using Prefix=$PREFIX Environment=$ENVIRONMENT Region=$REGION"

acct_json="$(aws sts get-caller-identity --region "$REGION" --output json)"
log "AWS Account: $(jq -r '.Account' <<<"$acct_json")"
log "Caller ARN : $(jq -r '.Arn' <<<"$acct_json")"

azs="$(get_two_azs "$REGION")"
log "Selected AZs: $azs"

log "Context OK. Next: ./03-Create-Network.sh"

