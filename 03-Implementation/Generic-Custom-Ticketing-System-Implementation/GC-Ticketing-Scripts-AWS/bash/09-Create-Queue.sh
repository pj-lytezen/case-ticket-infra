#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 09-Create-Queue.sh
#
# Creates SQS queues used for:
# - ingestion tasks
# - outbox processing
# - ticket sync events
#
# For simplicity, we create:
# - <prefix>-jobs (main queue)
# - <prefix>-jobs-dlq (dead-letter queue)
#
# Idempotency:
# - If a queue exists, we reuse its URL and ensure desired attributes are set.
# ------------------------------------------------------------

parse_args_prefix_env_region "$@"

require_cmd aws

ensure_queue_url() {
  local name="$1"
  local url=""
  if url="$(aws sqs get-queue-url --region "$REGION" --queue-name "$name" --query QueueUrl --output text 2>/dev/null)"; then
    log "Queue exists: $name"
    printf '%s' "$url"
    return
  fi
  log "Creating queue: $name"
  url="$(aws sqs create-queue --region "$REGION" --queue-name "$name" --query QueueUrl --output text)"
  printf '%s' "$url"
}

DLQ_NAME="$PREFIX-jobs-dlq"
DLQ_URL="$(ensure_queue_url "$DLQ_NAME")"

# Ensure DLQ retention is 14 days.
aws sqs set-queue-attributes --region "$REGION" --queue-url "$DLQ_URL" \
  --attributes MessageRetentionPeriod=1209600 >/dev/null

DLQ_ARN="$(aws sqs get-queue-attributes --region "$REGION" --queue-url "$DLQ_URL" --attribute-names QueueArn --query 'Attributes.QueueArn' --output text)"
REDRIVE="$(printf '{"deadLetterTargetArn":"%s","maxReceiveCount":5}' "$DLQ_ARN")"

JOBS_NAME="$PREFIX-jobs"
JOBS_URL="$(ensure_queue_url "$JOBS_NAME")"

# Ensure main queue attributes (visibility timeout, retention, DLQ).
aws sqs set-queue-attributes --region "$REGION" --queue-url "$JOBS_URL" \
  --attributes VisibilityTimeout=60 MessageRetentionPeriod=345600 RedrivePolicy="$REDRIVE" >/dev/null

log "Queueing complete."
log "Jobs queue URL: $JOBS_URL"
log "DLQ  queue URL: $DLQ_URL"
log "Next: ./10-Validate-Queue.sh"

