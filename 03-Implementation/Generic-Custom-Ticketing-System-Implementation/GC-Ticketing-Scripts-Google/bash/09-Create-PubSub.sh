#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 09-Create-PubSub.sh (GCP)
#
# Creates Pub/Sub topics and a subscription for async jobs/outbox:
# - Topic: <prefix>-jobs
# - DLQ topic: <prefix>-jobs-dlq
# - Subscription: <prefix>-jobs-sub with dead-letter policy
#
# Idempotency:
# - Topics/subscription are checked before create.
# ------------------------------------------------------------

parse_args_prefix_project_region_zone "$@"

require_cmd gcloud

gcloud config set project "$PROJECT_ID" >/dev/null

TOPIC="$(to_gc_name "$PREFIX-jobs")"
DLQ="$(to_gc_name "$PREFIX-jobs-dlq")"
SUB="$(to_gc_name "$PREFIX-jobs-sub")"

if gcloud pubsub topics describe "$TOPIC" >/dev/null 2>&1; then
  log "Topic exists: $TOPIC"
else
  log "Creating topic: $TOPIC"
  gcloud pubsub topics create "$TOPIC" >/dev/null
fi

if gcloud pubsub topics describe "$DLQ" >/dev/null 2>&1; then
  log "Topic exists: $DLQ"
else
  log "Creating DLQ topic: $DLQ"
  gcloud pubsub topics create "$DLQ" >/dev/null
fi

if gcloud pubsub subscriptions describe "$SUB" >/dev/null 2>&1; then
  log "Subscription exists: $SUB"
else
  log "Creating subscription: $SUB (with DLQ)"
  gcloud pubsub subscriptions create "$SUB" --topic "$TOPIC" \
    --ack-deadline=60 \
    --dead-letter-topic="$DLQ" \
    --max-delivery-attempts=5 >/dev/null
fi

log "Pub/Sub complete."
log "Next: ./10-Validate-PubSub.sh"

