#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 10-Validate-PubSub.sh (GCP)
#
# Manual verification (GCP Console):
# - Pub/Sub -> Topics: confirm jobs and jobs-dlq topics exist
# - Pub/Sub -> Subscriptions: confirm jobs-sub exists and DLQ policy is set
# ------------------------------------------------------------

parse_args_prefix_project_region_zone "$@"

require_cmd gcloud

gcloud config set project "$PROJECT_ID" >/dev/null

TOPIC="$(to_gc_name "$PREFIX-jobs")"
DLQ="$(to_gc_name "$PREFIX-jobs-dlq")"
SUB="$(to_gc_name "$PREFIX-jobs-sub")"

gcloud pubsub topics describe "$TOPIC" >/dev/null
gcloud pubsub topics describe "$DLQ" >/dev/null
gcloud pubsub subscriptions describe "$SUB" --format="yaml(name,topic,deadLetterPolicy)" | sed 's/^/  /'

