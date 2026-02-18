#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# Common helpers for Google Cloud bash provisioning scripts (gcloud based)
# -------------------------------------------------------------------

log() { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found on PATH."
}

to_gc_name() {
  # GCP naming:
  # - lowercase letters, digits, hyphens
  # - no leading/trailing hyphen
  local base="$1"
  local clean
  clean="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9-]+/-/g; s/-+/-/g; s/^-//; s/-$//')"
  # Truncate to 63 chars (common limit for many GCP resources).
  if [[ "${#clean}" -gt 63 ]]; then
    clean="${clean:0:63}"
    clean="$(printf '%s' "$clean" | sed -E 's/-$//')"
  fi
  printf '%s' "$clean"
}

parse_args_prefix_project_region_zone() {
  PREFIX="gc-tkt-prod"
  PROJECT_ID=""
  REGION="us-central1"
  ZONE="us-central1-a"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --prefix|-Prefix) PREFIX="$2"; shift 2;;
      --project-id|--ProjectId) PROJECT_ID="$2"; shift 2;;
      --region|-Region) REGION="$2"; shift 2;;
      --zone|-Zone) ZONE="$2"; shift 2;;
      *) die "Unknown argument: $1";;
    esac
  done
  [[ -n "$PROJECT_ID" ]] || die "--project-id is required."
}

