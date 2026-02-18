param(
  [string]$Prefix = "gc-tkt-prod",
  [string]$Region = "us-east-1"
)

. "$PSScriptRoot\\_common.ps1"

<#
  06-Validate-Security.ps1

  Validates the security primitives created by 05-Create-Security.ps1.

  Manual verification (AWS Console):
  - KMS -> Customer managed keys: confirm alias/$Prefix-kms exists and rotation is enabled
  - Secrets Manager -> Secrets: confirm $Prefix/rds/master and $Prefix/app/config exist
#>

Assert-CommandExists -Name "aws"

$kmsAliasName = "alias/$Prefix-kms"
$aliasList = Invoke-AwsJson -Command "kms list-aliases" -Region $Region
$alias = $aliasList.Aliases | Where-Object { $_.AliasName -eq $kmsAliasName } | Select-Object -First 1
if (-not $alias) { throw "Missing KMS alias: $kmsAliasName" }
Write-Host "KMS alias OK: $($alias.AliasName) -> $($alias.TargetKeyId)"

foreach ($name in @("$Prefix/rds/master", "$Prefix/app/config")) {
  $sec = Invoke-AwsJson -Command "secretsmanager describe-secret --secret-id `"$name`"" -Region $Region
  Write-Host "Secret OK: $name (ARN=$($sec.ARN))"
}

