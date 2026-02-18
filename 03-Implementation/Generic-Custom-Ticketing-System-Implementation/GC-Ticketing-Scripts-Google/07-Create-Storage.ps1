param(
  [string]$Prefix = "gc-tkt-prod",
  [Parameter(Mandatory=$true)][string]$ProjectId,
  [string]$Region = "us-central1"
)

. "$PSScriptRoot\\_common.ps1"

<#
  07-Create-Storage.ps1 (GCP)

  Creates Cloud Storage buckets for:
  - documents
  - attachments

  Idempotency:
  - Bucket names are global; we include ProjectId to reduce collisions.
  - If buckets exist, script ensures baseline security settings.
#>

Assert-CommandExists -Name "gcloud"

function Ensure-Bucket {
  param([string]$BucketName)
  $exists = $false
  try { Invoke-Expression "gcloud storage buckets describe gs://$BucketName | Out-Null" | Out-Null; $exists = $true } catch { }

  if (-not $exists) {
    Write-Host "Creating bucket: $BucketName"
    Invoke-Expression "gcloud storage buckets create gs://$BucketName --location=$Region --uniform-bucket-level-access" | Out-Null
  } else {
    Write-Host "Bucket exists: $BucketName"
  }

  # Baseline hardening:
  # - Uniform bucket-level access prevents object-level ACL drift.
  # - Public access prevention enforces “no public exposure by accident”.
  Invoke-Expression "gcloud storage buckets update gs://$BucketName --public-access-prevention=enforced" | Out-Null
}

$docsBucket = To-GcName -Base ("$Prefix-$ProjectId-docs")
$attBucket  = To-GcName -Base ("$Prefix-$ProjectId-attachments")

Ensure-Bucket -BucketName $docsBucket
Ensure-Bucket -BucketName $attBucket

Write-Host "Storage complete."
Write-Host "Docs bucket       : gs://$docsBucket"
Write-Host "Attachments bucket: gs://$attBucket"
Write-Host "Next: 08-Validate-Storage.ps1"

