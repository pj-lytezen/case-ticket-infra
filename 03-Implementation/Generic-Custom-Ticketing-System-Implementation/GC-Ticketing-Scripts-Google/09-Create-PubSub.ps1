param(
  [string]$Prefix = "gc-tkt-prod",
  [Parameter(Mandatory=$true)][string]$ProjectId
)

. "$PSScriptRoot\\_common.ps1"

<#
  09-Create-PubSub.ps1 (GCP)

  Creates Pub/Sub topics and subscription for async jobs/outbox processing:
  - Topic: <prefix>-jobs
  - DLQ topic: <prefix>-jobs-dlq
  - Subscription: <prefix>-jobs-sub with dead-letter policy

  Design alignment:
  - Queue isolates ingestion/embedding/outbox workloads from user request path.

  Idempotency:
  - Topics/subscriptions are checked before creation.
#>

Assert-CommandExists -Name "gcloud"

$topic = To-GcName -Base ("$Prefix-jobs")
$dlqTopic = To-GcName -Base ("$Prefix-jobs-dlq")
$sub = To-GcName -Base ("$Prefix-jobs-sub")

function Ensure-Topic {
  param([string]$Name)
  $exists = $false
  try { Invoke-Expression "gcloud pubsub topics describe $Name | Out-Null" | Out-Null; $exists = $true } catch { }
  if (-not $exists) {
    Write-Host "Creating topic: $Name"
    Invoke-Expression "gcloud pubsub topics create $Name" | Out-Null
  } else {
    Write-Host "Topic exists: $Name"
  }
}

Ensure-Topic -Name $topic
Ensure-Topic -Name $dlqTopic

$subExists = $false
try { Invoke-Expression "gcloud pubsub subscriptions describe $sub | Out-Null" | Out-Null; $subExists = $true } catch { }
if (-not $subExists) {
  Write-Host "Creating subscription: $sub (with DLQ)"
  Invoke-Expression @"
gcloud pubsub subscriptions create $sub --topic $topic `
  --ack-deadline=60 `
  --dead-letter-topic=$dlqTopic `
  --max-delivery-attempts=5
"@ | Out-Null
} else {
  Write-Host "Subscription exists: $sub"
}

Write-Host "Pub/Sub complete."
Write-Host "Next: 10-Validate-PubSub.ps1"

