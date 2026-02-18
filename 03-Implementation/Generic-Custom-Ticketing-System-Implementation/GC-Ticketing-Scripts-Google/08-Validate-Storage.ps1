param(
  [string]$Prefix = "gc-tkt-prod",
  [Parameter(Mandatory=$true)][string]$ProjectId,
  [string]$Region = "us-central1"
)

. "$PSScriptRoot\\_common.ps1"

<#
  08-Validate-Storage.ps1 (GCP)

  Validates buckets created by 07-Create-Storage.ps1.

  Manual verification (GCP Console):
  - Cloud Storage -> Buckets: confirm docs/attachments buckets exist
  - Permissions: confirm Public access prevention is enforced
#>

Assert-CommandExists -Name "gcloud"

foreach ($b in @(
  To-GcName -Base ("$Prefix-$ProjectId-docs"),
  To-GcName -Base ("$Prefix-$ProjectId-attachments")
)) {
  Invoke-Expression "gcloud storage buckets describe gs://$b | Out-Null" | Out-Null
  $pap = (Invoke-Expression "gcloud storage buckets describe gs://$b --format=`"value(iamConfiguration.publicAccessPrevention)`"").Trim()
  Write-Host "Bucket OK: $b publicAccessPrevention=$pap"
}

