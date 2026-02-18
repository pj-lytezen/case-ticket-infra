param(
  [string]$Prefix = "gc-tkt-prod",
  [Parameter(Mandatory=$true)][string]$ProjectId,
  [string]$Region = "us-central1"
)

. "$PSScriptRoot\\_common.ps1"

<#
  06-Validate-Security.ps1 (GCP)

  Validates KMS and Secret Manager.

  Manual verification (GCP Console):
  - Security -> Key Management: confirm key ring and key exist
  - Security -> Secret Manager: confirm secrets exist and have at least 1 version
#>

Assert-CommandExists -Name "gcloud"

$keyRing = To-GcName -Base ("kr-$Prefix")
$cryptoKey = To-GcName -Base ("key-$Prefix")

Invoke-Expression "gcloud kms keyrings describe $keyRing --location $Region | Out-Null" | Out-Null
Invoke-Expression "gcloud kms keys describe $cryptoKey --keyring $keyRing --location $Region | Out-Null" | Out-Null
Write-Host "KMS OK: $keyRing/$cryptoKey"

foreach ($s in @((To-GcName -Base "$Prefix-sql-password"), (To-GcName -Base "$Prefix-app-config"))) {
  Invoke-Expression "gcloud secrets describe $s | Out-Null" | Out-Null
  $vers = Invoke-GcloudJson "secrets versions list $s"
  Write-Host "Secret OK: $s versions=$($vers.Count)"
}

