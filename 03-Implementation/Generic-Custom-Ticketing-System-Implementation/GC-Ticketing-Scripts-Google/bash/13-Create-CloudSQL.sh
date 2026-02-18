#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ------------------------------------------------------------
# 13-Create-CloudSQL.sh (GCP)
#
# Creates Cloud SQL for PostgreSQL with private IP:
# - Reserves a peering range for Private Service Access (PSA)
# - Connects Service Networking to the VPC
# - Creates Cloud SQL instance (regional HA optional)
# - Creates database: gc_ticketing
# - Creates application user: gc_admin
#
# Idempotency:
# - Range/connection/instance/db/user are checked before create.
#
# Important:
# - Requires servicenetworking API enabled (done in 01-Context.sh).
# ------------------------------------------------------------

PREFIX="gc-tkt-prod"
PROJECT_ID=""
REGION="us-central1"
TIER="db-custom-2-7680"
STORAGE_GB=256
HA="true"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix|-Prefix) PREFIX="$2"; shift 2;;
    --project-id|--ProjectId) PROJECT_ID="$2"; shift 2;;
    --region|-Region) REGION="$2"; shift 2;;
    --tier|-Tier) TIER="$2"; shift 2;;
    --storage-gb|--StorageGb) STORAGE_GB="$2"; shift 2;;
    --high-availability|--HighAvailability) HA="$2"; shift 2;;
    *) die "Unknown argument: $1";;
  esac
done
[[ -n "$PROJECT_ID" ]] || die "--project-id is required."

require_cmd gcloud

gcloud config set project "$PROJECT_ID" >/dev/null

NET="$(to_gc_name "net-$PREFIX")"
RANGE="$(to_gc_name "psa-$PREFIX")"
SQL="$(to_gc_name "sql-$PREFIX")"

if gcloud compute addresses describe "$RANGE" --global >/dev/null 2>&1; then
  log "PSA range exists: $RANGE"
else
  log "Reserving global address range for Service Networking: $RANGE"
  gcloud compute addresses create "$RANGE" --global \
    --purpose=VPC_PEERING \
    --prefix-length=16 \
    --network="$NET" \
    --description="PSA range for Cloud SQL private IP" >/dev/null
fi

# Connect service networking (if already connected, command may error; treat as already done).
log "Ensuring Service Networking connection exists..."
if ! gcloud services vpc-peerings connect --service=servicenetworking.googleapis.com --ranges="$RANGE" --network="$NET" >/dev/null 2>&1; then
  warn "Service Networking connect returned an error (often means it already exists). Continuing..."
fi

PWD_SECRET="$(to_gc_name "$PREFIX-sql-password")"
DB_PASS="$(gcloud secrets versions access latest --secret="$PWD_SECRET" | tr -d '\r')"

if gcloud sql instances describe "$SQL" >/dev/null 2>&1; then
  log "Cloud SQL instance exists: $SQL"
else
  availability="REGIONAL"
  if [[ "$HA" == "false" || "$HA" == "False" || "$HA" == "0" ]]; then
    availability="ZONAL"
  fi
  log "Creating Cloud SQL instance: $SQL (availability=$availability)"
  gcloud sql instances create "$SQL" --database-version=POSTGRES_15 --region="$REGION" \
    --network="projects/$PROJECT_ID/global/networks/$NET" \
    --no-assign-ip \
    --tier="$TIER" \
    --storage-size="$STORAGE_GB" \
    --availability-type="$availability" \
    --backup-start-time=03:00 \
    --root-password="$DB_PASS" >/dev/null
fi

DB="gc_ticketing"
if gcloud sql databases describe "$DB" --instance "$SQL" >/dev/null 2>&1; then
  log "Database exists: $DB"
else
  log "Creating database: $DB"
  gcloud sql databases create "$DB" --instance "$SQL" >/dev/null
fi

USER="gc_admin"
if gcloud sql users list --instance "$SQL" --format="value(name)" | tr -d '\r' | grep -qx "$USER"; then
  log "DB user exists: $USER"
else
  log "Creating DB user: $USER"
  gcloud sql users create "$USER" --instance "$SQL" --password "$DB_PASS" >/dev/null
fi

log "Cloud SQL provisioning complete."
log "Next: ./14-Validate-CloudSQL.sh"

