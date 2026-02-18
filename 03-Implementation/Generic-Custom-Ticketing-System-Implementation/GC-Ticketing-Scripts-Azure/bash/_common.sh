#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# Common helpers for Azure bash provisioning scripts (Azure CLI based)
# -------------------------------------------------------------------

log() { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found on PATH."
}

rg_name() {
  local prefix="$1"
  printf 'rg-%s' "$prefix"
}

az_sub_id() {
  az account show --query id -o tsv | tr -d '\r'
}

det_suffix() {
  # Stable suffix derived from subscription id to reduce global-name collisions.
  # Equivalent to the PowerShell version: remove '-' and take first 6.
  local sid
  sid="$(az_sub_id)"
  sid="${sid//-/}"
  printf '%s' "${sid:0:6}" | tr '[:upper:]' '[:lower:]'
}

to_global_name() {
  # Azure global name normalization:
  # - lowercase
  # - alphanumeric only
  # - truncated to max length
  local base="$1" max_len="$2"
  local clean
  clean="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')"
  if [[ "${#clean}" -gt "$max_len" ]]; then
    clean="${clean:0:$max_len}"
  fi
  printf '%s' "$clean"
}

ensure_rg() {
  local rg="$1" location="$2"
  local exists
  exists="$(az group exists --name "$rg" -o tsv | tr -d '\r')"
  if [[ "$exists" == "true" ]]; then
    log "Resource group exists: $rg"
    return
  fi
  log "Creating resource group: $rg ($location)"
  az group create --name "$rg" --location "$location" --tags Project=SupportTicketAutomation >/dev/null
}

parse_args_prefix_location() {
  PREFIX="gc-tkt-prod"
  LOCATION="eastus"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --prefix|-Prefix) PREFIX="$2"; shift 2;;
      --location|-Location|--region) LOCATION="$2"; shift 2;;
      *) die "Unknown argument: $1";;
    esac
  done
}

