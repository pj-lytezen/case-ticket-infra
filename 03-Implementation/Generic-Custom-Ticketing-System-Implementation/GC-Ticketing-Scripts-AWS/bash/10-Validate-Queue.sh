#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 10-Validate-Queue.sh
#
# Validates SQS queues and prints key attributes.
#
# Manual verification (AWS Console):
# - SQS -> Queues: confirm <prefix>-jobs and <prefix>-jobs-dlq exist
# - Main queue -> Redrive policy points to DLQ
# ------------------------------------------------------------

parse_args_prefix_env_region "$@"

require_cmd aws
require_cmd jq

for name in "$PREFIX-jobs" "$PREFIX-jobs-dlq"; do
  url="$(aws sqs get-queue-url --region "$REGION" --queue-name "$name" --query QueueUrl --output text)"
  attrs="$(aws sqs get-queue-attributes --region "$REGION" --queue-url "$url" --attribute-names All --output json)"
  log "Queue OK: $name"
  log "  URL: $url"
  log "  ARN: $(jq -r '.Attributes.QueueArn' <<<"$attrs")"
  rp="$(jq -r '.Attributes.RedrivePolicy // empty' <<<"$attrs")"
  [[ -n "$rp" ]] && log "  RedrivePolicy: $rp"
done

