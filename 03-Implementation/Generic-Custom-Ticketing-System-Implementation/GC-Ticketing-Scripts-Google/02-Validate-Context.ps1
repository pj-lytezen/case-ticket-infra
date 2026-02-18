param(
  [string]$Prefix = "gc-tkt-prod",
  [Parameter(Mandatory=$true)][string]$ProjectId,
  [string]$Region = "us-central1"
)

. "$PSScriptRoot\\_common.ps1"

<#
  02-Validate-Context.ps1 (GCP)

  Validation companion for 01-Context.ps1.

  Manual verification (GCP Console):
  - Confirm the correct Project is selected in the project picker.
  - APIs & Services -> Enabled APIs: confirm Compute Engine, Kubernetes Engine, Cloud SQL, Secret Manager, KMS, Pub/Sub are enabled.
#>

Assert-CommandExists -Name "gcloud"

$proj = Invoke-GcloudJson "projects describe $ProjectId"
Write-Host "Project OK: $($proj.projectId) number=$($proj.projectNumber)"

$enabled = Invoke-GcloudJson "services list --enabled"
Write-Host ("Enabled services count: " + $enabled.Count)

