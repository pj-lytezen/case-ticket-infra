param(
  [string]$Prefix = "gc-tkt-prod",
  [string]$Environment = "prod",
  [string]$Region = "us-east-1"
)

. "$PSScriptRoot\\_common.ps1"

<#
  01-Context.ps1

  Purpose:
  - “Pre-flight” checks so later scripts fail early and with clear errors.
  - Confirms AWS CLI is installed and credentials are usable.

  Idempotency:
  - This script does not create cloud resources; it validates local/identity context.
#>

Assert-CommandExists -Name "aws"

Write-Host "Using Prefix=$Prefix Environment=$Environment Region=$Region"

# Confirm we can authenticate and identify the AWS account.
$identity = Invoke-AwsJson -Command "sts get-caller-identity" -Region $Region
Write-Host "AWS Account: $($identity.Account)"
Write-Host "Caller ARN : $($identity.Arn)"

# Confirm the region exists and has at least two AZs (needed for HA network + EKS + RDS).
$azs = Get-AvailabilityZones2 -Region $Region
Write-Host "Selected AZs: $($azs -join ', ')"

Write-Host "Context OK. Next: run 02-Validate-Context.ps1 (optional) then 03-Create-Network.ps1."

