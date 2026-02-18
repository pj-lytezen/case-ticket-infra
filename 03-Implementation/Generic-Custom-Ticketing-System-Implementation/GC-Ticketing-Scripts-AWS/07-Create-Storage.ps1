param(
  [string]$Prefix = "gc-tkt-prod",
  [string]$Environment = "prod",
  [string]$Region = "us-east-1"
)

. "$PSScriptRoot\\_common.ps1"

<#
  07-Create-Storage.ps1

  Creates object storage for:
  - documents (ingested KB/docs)
  - attachments (customer-provided files)

  Design alignment:
  - The design stores raw docs/attachments in object storage and indexes text/embeddings in PostgreSQL.

  Idempotency:
  - S3 bucket names are globally unique; we derive deterministic names using AWS Account ID.
  - Script checks existence with HeadBucket before creating.
#>

Assert-CommandExists -Name "aws"

$accountId = Get-AwsAccountId -Region $Region

function Ensure-Bucket {
  param([string]$BucketName)

  $exists = $false
  try {
    Invoke-Expression "aws s3api head-bucket --region $Region --bucket $BucketName | Out-Null" | Out-Null
    $exists = $true
  } catch { }

  if (-not $exists) {
    Write-Host "Creating bucket: $BucketName"

    # us-east-1 requires no LocationConstraint; other regions do.
    if ($Region -eq "us-east-1") {
      Invoke-Expression "aws s3api create-bucket --region $Region --bucket $BucketName | Out-Null" | Out-Null
    } else {
      Invoke-Expression "aws s3api create-bucket --region $Region --bucket $BucketName --create-bucket-configuration LocationConstraint=$Region | Out-Null" | Out-Null
    }
  } else {
    Write-Host "Bucket exists: $BucketName"
  }

  # Security baseline: block all public access.
  Invoke-Expression "aws s3api put-public-access-block --region $Region --bucket $BucketName --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true | Out-Null" | Out-Null

  # Versioning improves recovery from accidental overwrites/deletes.
  Invoke-Expression "aws s3api put-bucket-versioning --region $Region --bucket $BucketName --versioning-configuration Status=Enabled | Out-Null" | Out-Null

  # Default encryption: SSE-S3 is simplest. If you want KMS, switch to SSE-KMS and reference alias/$Prefix-kms.
  Invoke-Expression "aws s3api put-bucket-encryption --region $Region --bucket $BucketName --server-side-encryption-configuration '{\"Rules\":[{\"ApplyServerSideEncryptionByDefault\":{\"SSEAlgorithm\":\"AES256\"}}]}' | Out-Null" | Out-Null
}

$docsBucket = ("$Prefix-$accountId-docs").ToLower()
$attBucket  = ("$Prefix-$accountId-attachments").ToLower()

Ensure-Bucket -BucketName $docsBucket
Ensure-Bucket -BucketName $attBucket

Write-Host "Storage complete."
Write-Host "Docs bucket       : $docsBucket"
Write-Host "Attachments bucket: $attBucket"
Write-Host "Next: 08-Validate-Storage.ps1"

