param(
  [string]$Prefix = "gc-tkt-prod",
  [Parameter(Mandatory=$true)][string]$ProjectId,
  [string]$Region = "us-central1"
)

. "$PSScriptRoot\\_common.ps1"

<#
  05-Create-Security.ps1 (GCP)

  Creates:
  - Cloud KMS key ring + crypto key (encryption primitives)
  - Secret Manager secrets (Cloud SQL password, app config)

  Why:
  - Keeps credentials out of scripts and terminals.
  - Enables encryption at rest patterns and future envelope encryption for sensitive artifacts.

  Idempotency:
  - Uses describe checks; creates only if missing.
#>

Assert-CommandExists -Name "gcloud"

$keyRing = To-GcName -Base ("kr-$Prefix")
$cryptoKey = To-GcName -Base ("key-$Prefix")

function Ensure-KmsKeyRing {
  try {
    Invoke-Expression "gcloud kms keyrings describe $keyRing --location $Region | Out-Null" | Out-Null
    Write-Host "KMS key ring exists: $keyRing"
  } catch {
    Write-Host "Creating KMS key ring: $keyRing"
    Invoke-Expression "gcloud kms keyrings create $keyRing --location $Region" | Out-Null
  }
}

function Ensure-KmsCryptoKey {
  try {
    Invoke-Expression "gcloud kms keys describe $cryptoKey --keyring $keyRing --location $Region | Out-Null" | Out-Null
    Write-Host "KMS key exists: $cryptoKey"
  } catch {
    Write-Host "Creating KMS crypto key: $cryptoKey"
    Invoke-Expression "gcloud kms keys create $cryptoKey --keyring $keyRing --location $Region --purpose encryption" | Out-Null
  }
}

function New-RandomPassword {
  param([int]$Length = 28)
  $chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789"
  -join (1..$Length | ForEach-Object { $chars[(Get-Random -Minimum 0 -Maximum $chars.Length)] })
}

function Ensure-Secret {
  param([string]$Name,[string]$Value)
  $exists = $false
  try { Invoke-Expression "gcloud secrets describe $Name | Out-Null" | Out-Null; $exists = $true } catch { }
  if (-not $exists) {
    Write-Host "Creating secret: $Name"
    Invoke-Expression "gcloud secrets create $Name --replication-policy=automatic" | Out-Null
  } else {
    Write-Host "Secret exists: $Name"
  }

  # Add a secret version only if there are no versions yet (prevents duplicating versions on re-run).
  $versions = Invoke-GcloudJson "secrets versions list $Name"
  if ($versions.Count -eq 0) {
    Write-Host "Adding initial secret version for: $Name"
    $tmp = New-TemporaryFile
    Set-Content -Path $tmp.FullName -Value $Value -NoNewline -Encoding UTF8
    Invoke-Expression "gcloud secrets versions add $Name --data-file=$($tmp.FullName)" | Out-Null
  } else {
    Write-Host "Secret already has versions; not adding a new one (idempotency)."
  }
}

Ensure-KmsKeyRing
Ensure-KmsCryptoKey

Ensure-Secret -Name (To-GcName -Base "$Prefix-sql-password") -Value (New-RandomPassword)
Ensure-Secret -Name (To-GcName -Base "$Prefix-app-config") -Value (@{ environment="prod"; notes="fill after provisioning" } | ConvertTo-Json -Compress)

Write-Host "Security complete."
Write-Host "Next: 06-Validate-Security.ps1"

