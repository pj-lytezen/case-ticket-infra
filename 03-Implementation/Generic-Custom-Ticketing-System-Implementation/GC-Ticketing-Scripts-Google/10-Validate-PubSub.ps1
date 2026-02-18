param(
  [string]$Prefix = "gc-tkt-prod",
  [Parameter(Mandatory=$true)][string]$ProjectId
)

. "$PSScriptRoot\\_common.ps1"

<#
  10-Validate-PubSub.ps1 (GCP)

  Validates topics/subscription created by 09-Create-PubSub.ps1.

  Manual verification (GCP Console):
  - Pub/Sub -> Topics: confirm jobs and jobs-dlq topics exist
  - Pub/Sub -> Subscriptions: confirm jobs-sub exists and DLQ policy is set
#>

Assert-CommandExists -Name "gcloud"

$topic = To-GcName -Base ("$Prefix-jobs")
$dlqTopic = To-GcName -Base ("$Prefix-jobs-dlq")
$sub = To-GcName -Base ("$Prefix-jobs-sub")

Invoke-Expression "gcloud pubsub topics describe $topic | Out-Null" | Out-Null
Invoke-Expression "gcloud pubsub topics describe $dlqTopic | Out-Null" | Out-Null
$s = Invoke-GcloudJson "pubsub subscriptions describe $sub"
Write-Host "Subscription OK: $($s.name)"
Write-Host "  topic: $($s.topic)"
Write-Host "  deadLetterTopic: $($s.deadLetterPolicy.deadLetterTopic)"

