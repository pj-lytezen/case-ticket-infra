param(
  [string]$Prefix = "gc-tkt-prod",
  [Parameter(Mandatory=$true)][string]$ProjectId,
  [string]$Region = "us-central1",
  [string]$Zone = "us-central1-a"
)

. "$PSScriptRoot\\_common.ps1"

<#
  01-Context.ps1 (GCP)

  Purpose:
  - Pre-flight checks: confirm gcloud is installed and authenticated.
  - Set the active project/region/zone (so later scripts don’t deploy to the wrong project).
  - Enable required APIs up front (reduces “mysterious failures” later).

  Idempotency:
  - No resources are created besides enabling APIs (enabling an API is idempotent).
#>

Assert-CommandExists -Name "gcloud"

Write-Host "Prefix=$Prefix ProjectId=$ProjectId Region=$Region Zone=$Zone"

# Set active project and default compute region/zone for convenience.
Invoke-Expression "gcloud config set project $ProjectId | Out-Null" | Out-Null
Invoke-Expression "gcloud config set compute/region $Region | Out-Null" | Out-Null
Invoke-Expression "gcloud config set compute/zone $Zone | Out-Null" | Out-Null

# Confirm authentication context.
$activeAcct = (Invoke-Expression "gcloud auth list --filter=status:ACTIVE --format=`"value(account)`"").Trim()
Write-Host "Active account: $activeAcct"

# Enable APIs required by the design.
$apis = @(
  "compute.googleapis.com",
  "container.googleapis.com",
  "sqladmin.googleapis.com",
  "servicenetworking.googleapis.com",
  "secretmanager.googleapis.com",
  "cloudkms.googleapis.com",
  "pubsub.googleapis.com",
  "logging.googleapis.com",
  "monitoring.googleapis.com",
  "artifactregistry.googleapis.com"
)

Write-Host "Enabling required APIs (safe to re-run)..."
Invoke-Expression ("gcloud services enable " + ($apis -join ' ')) | Out-Null

Write-Host "Context OK. Next: 03-Create-Network.ps1"

