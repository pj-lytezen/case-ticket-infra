param(
  [string]$Prefix = "gc-tkt-prod",
  [string]$Region = "us-east-1"
)

. "$PSScriptRoot\\_common.ps1"

<#
  09-Create-Queue.ps1

  Creates SQS queues used for:
  - ingestion tasks (document/case indexing)
  - outbox processing (durable side effects)
  - ticket sync events

  For simplicity, we provision one “jobs” queue + DLQ that you can subdivide later.
  In a mature system, you’ll likely create separate queues per workload with different retry/DLQ policies.

  Idempotency:
  - SQS queue name is unique within the account+region.
  - If the queue exists, we update its attributes (safe to re-run).
#>

Assert-CommandExists -Name "aws"

function Ensure-Queue {
  param(
    [string]$QueueName,
    [hashtable]$Attributes
  )

  $url = $null
  try {
    $res = Invoke-AwsJson -Command "sqs get-queue-url --queue-name $QueueName" -Region $Region
    $url = $res.QueueUrl
    Write-Host "Queue exists: $QueueName"
  } catch { }

  if (-not $url) {
    Write-Host "Creating queue: $QueueName"
    $attrPairs = $Attributes.Keys | ForEach-Object { "$_=$($Attributes[$_])" }
    $attrArg = ($attrPairs -join ',')
    $res = Invoke-AwsJson -Command "sqs create-queue --queue-name $QueueName --attributes $attrArg" -Region $Region
    $url = $res.QueueUrl
  } else {
    # Ensure desired attributes are set even if queue existed already.
    $attrPairs = $Attributes.Keys | ForEach-Object { "$_=$($Attributes[$_])" }
    $attrArg = ($attrPairs -join ',')
    Invoke-Expression "aws sqs set-queue-attributes --region $Region --queue-url `"$url`" --attributes $attrArg | Out-Null" | Out-Null
  }

  return $url
}

$dlqName = "$Prefix-jobs-dlq"
$dlqUrl = Ensure-Queue -QueueName $dlqName -Attributes @{
  MessageRetentionPeriod = "1209600" # 14 days
}

$dlqArn = (Invoke-AwsJson -Command "sqs get-queue-attributes --queue-url `"$dlqUrl`" --attribute-names QueueArn" -Region $Region).Attributes.QueueArn

# Redrive policy: after N receives, message goes to DLQ.
$redrive = (@{ deadLetterTargetArn = $dlqArn; maxReceiveCount = 5 } | ConvertTo-Json -Compress)

$jobsName = "$Prefix-jobs"
$jobsUrl = Ensure-Queue -QueueName $jobsName -Attributes @{
  VisibilityTimeout = "60"
  MessageRetentionPeriod = "345600" # 4 days
  RedrivePolicy = $redrive
}

Write-Host "Queueing complete."
Write-Host "Jobs queue URL: $jobsUrl"
Write-Host "DLQ  queue URL: $dlqUrl"
Write-Host "Next: 10-Validate-Queue.ps1"

