param(
  [string]$Prefix = "gc-tkt-prod",
  [string]$Region = "us-east-1"
)

. "$PSScriptRoot\\_common.ps1"

<#
  10-Validate-Queue.ps1

  Validates queues created by 09-Create-Queue.ps1.

  Manual verification (AWS Console):
  - SQS -> Queues: confirm $Prefix-jobs and $Prefix-jobs-dlq exist
  - Queue details: confirm Redrive policy points to the DLQ
#>

Assert-CommandExists -Name "aws"

foreach ($name in @("$Prefix-jobs", "$Prefix-jobs-dlq")) {
  $url = (Invoke-AwsJson -Command "sqs get-queue-url --queue-name $name" -Region $Region).QueueUrl
  $attrs = Invoke-AwsJson -Command "sqs get-queue-attributes --queue-url `"$url`" --attribute-names All" -Region $Region
  Write-Host "Queue OK: $name"
  Write-Host "  URL: $url"
  Write-Host "  ARN: $($attrs.Attributes.QueueArn)"
  if ($attrs.Attributes.RedrivePolicy) {
    Write-Host "  RedrivePolicy: $($attrs.Attributes.RedrivePolicy)"
  }
}

