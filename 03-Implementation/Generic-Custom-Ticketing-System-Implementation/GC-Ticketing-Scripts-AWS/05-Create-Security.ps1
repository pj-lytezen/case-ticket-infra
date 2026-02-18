param(
  [string]$Prefix = "gc-tkt-prod",
  [string]$Environment = "prod",
  [string]$Region = "us-east-1"
)

. "$PSScriptRoot\\_common.ps1"

<#
  05-Create-Security.ps1

  Creates security primitives used across the system:
  - KMS key + alias (for encrypting S3, secrets, and optionally RDS)
  - Secrets Manager secrets (for DB credentials and application configuration)

  Why:
  - Centralizes encryption keys and secrets so later scripts can reference them.
  - Avoids embedding passwords in scripts or shell history.

  Idempotency strategy:
  - KMS: check alias; if present, reuse the key.
  - Secrets Manager: check by secret name; if present, do not overwrite by default.
#>

Assert-CommandExists -Name "aws"

$kmsAliasName = "alias/$Prefix-kms"
$aliasList = Invoke-AwsJson -Command "kms list-aliases" -Region $Region
$existingAlias = $aliasList.Aliases | Where-Object { $_.AliasName -eq $kmsAliasName } | Select-Object -First 1

if ($existingAlias -and $existingAlias.TargetKeyId) {
  Write-Host "KMS alias exists: $kmsAliasName -> $($existingAlias.TargetKeyId)"
  $kmsKeyId = $existingAlias.TargetKeyId
} else {
  Write-Host "Creating KMS key for $kmsAliasName"

  # The default key policy allows the account to administer the key.
  # In a real production hardening pass, you should:
  # - restrict admin to a specific role
  # - create separate usage roles for apps
  $key = Invoke-AwsJson -Command "kms create-key --description `"$Prefix key for GC Ticketing`" --key-usage ENCRYPT_DECRYPT --origin AWS_KMS" -Region $Region
  $kmsKeyId = $key.KeyMetadata.KeyId

  # Enable annual rotation to reduce long-term blast radius.
  Invoke-Expression "aws kms enable-key-rotation --region $Region --key-id $kmsKeyId" | Out-Null

  Invoke-Expression "aws kms create-alias --region $Region --alias-name $kmsAliasName --target-key-id $kmsKeyId | Out-Null" | Out-Null
  Write-Host "Created KMS key: $kmsKeyId"
}

function New-RandomPassword {
  # Generates a reasonably strong password without special characters that often cause shell escaping issues.
  # You can increase complexity later; this is a safe baseline for CLI automation.
  param([int]$Length = 28)
  $chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789"
  -join (1..$Length | ForEach-Object { $chars[(Get-Random -Minimum 0 -Maximum $chars.Length)] })
}

function Ensure-Secret {
  param(
    [string]$Name,
    [string]$Description,
    [string]$SecretStringJson
  )

  try {
    $existing = Invoke-AwsJson -Command "secretsmanager describe-secret --secret-id `"$Name`"" -Region $Region
    Write-Host "Secret exists: $Name (ARN=$($existing.ARN))"
    return
  } catch {
    # Not found: create it.
  }

  Write-Host "Creating secret: $Name"
  # Note: If you need strict KMS control, include `--kms-key-id $kmsKeyId`.
  Invoke-Expression "aws secretsmanager create-secret --region $Region --name `"$Name`" --description `"$Description`" --secret-string `'$SecretStringJson`' | Out-Null" | Out-Null
}

# DB master secret used by the RDS creation script.
$dbUser = "gc_admin"
$dbPass = New-RandomPassword
$dbSecretName = "$Prefix/rds/master"
$dbSecretJson = (@{
  username = $dbUser
  password = $dbPass
  engine   = "postgres"
} | ConvertTo-Json -Compress)

Ensure-Secret -Name $dbSecretName -Description "Master credentials for $Prefix RDS Postgres" -SecretStringJson $dbSecretJson

# Placeholder “app config” secret - helps keep environment-specific values out of code.
$appCfgName = "$Prefix/app/config"
$appCfgJson = (@{
  environment = $Environment
  # Fill these in after provisioning:
  # db_host = ""
  # queue_url = ""
} | ConvertTo-Json -Compress)
Ensure-Secret -Name $appCfgName -Description "Application config for $Prefix" -SecretStringJson $appCfgJson

Write-Host "Security primitives complete."
Write-Host "Next: 06-Validate-Security.ps1"

