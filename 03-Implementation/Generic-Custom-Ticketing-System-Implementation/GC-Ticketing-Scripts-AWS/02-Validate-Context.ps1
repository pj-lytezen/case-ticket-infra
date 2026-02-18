param(
  [string]$Prefix = "gc-tkt-prod",
  [string]$Environment = "prod",
  [string]$Region = "us-east-1"
)

. "$PSScriptRoot\\_common.ps1"

<#
  02-Validate-Context.ps1

  Purpose:
  - Validation companion for 01-Context.ps1.
  - Re-checks identity and prints what a human should verify in the AWS Console.

  Manual verification (AWS Console):
  - IAM -> Users/Roles: confirm the principal used by AWS CLI has permissions for VPC, EKS, RDS, S3, SQS, KMS.
  - Billing -> Cost allocation tags: optionally activate Project/Environment tags for cost tracking.
#>

Assert-CommandExists -Name "aws"

$identity = Invoke-AwsJson -Command "sts get-caller-identity" -Region $Region
Write-Host "OK: Authenticated as $($identity.Arn) in account $($identity.Account) region $Region"

Write-Host "Reminder: Ensure you are operating in the intended AWS account/region before creating production resources."

