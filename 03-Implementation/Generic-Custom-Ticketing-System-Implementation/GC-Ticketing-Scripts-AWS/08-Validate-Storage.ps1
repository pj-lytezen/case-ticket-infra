param(
  [string]$Prefix = "gc-tkt-prod",
  [string]$Region = "us-east-1"
)

. "$PSScriptRoot\\_common.ps1"

<#
  08-Validate-Storage.ps1

  Validates S3 buckets created by 07-Create-Storage.ps1.

  Manual verification (AWS Console):
  - S3 -> Buckets: confirm docs/attachments buckets exist and “Block all public access” is ON.
  - S3 -> Bucket -> Properties: confirm Versioning is enabled and Default encryption is enabled.
#>

Assert-CommandExists -Name "aws"

$accountId = Get-AwsAccountId -Region $Region
$buckets = @(
  ("$Prefix-$accountId-docs").ToLower(),
  ("$Prefix-$accountId-attachments").ToLower()
)

foreach ($b in $buckets) {
  Invoke-Expression "aws s3api head-bucket --region $Region --bucket $b | Out-Null" | Out-Null
  $ver = Invoke-AwsJson -Command "s3api get-bucket-versioning --bucket $b" -Region $Region
  $enc = Invoke-AwsJson -Command "s3api get-bucket-encryption --bucket $b" -Region $Region
  Write-Host "Bucket OK: $b Versioning=$($ver.Status) Encryption=$($enc.ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm)"
}

