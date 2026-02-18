#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 14-Validate-CloudSQL.sh (GCP)
#
# Manual verification (GCP Console):
# - SQL -> Instances: confirm instance exists and has Private IP
# - SQL -> Databases: confirm gc_ticketing exists
# ------------------------------------------------------------

parse_args_prefix_project_region_zone "$@"

require_cmd gcloud

gcloud config set project "$PROJECT_ID" >/dev/null

SQL="$(to_gc_name "sql-$PREFIX")"
gcloud sql instances describe "$SQL" --format="yaml(name,state,region,settings.tier,settings.availabilityType,ipAddresses)" | sed 's/^/  /'
gcloud sql databases describe gc_ticketing --instance "$SQL" --format="value(name)" >/dev/null
log "Database OK: gc_ticketing"

