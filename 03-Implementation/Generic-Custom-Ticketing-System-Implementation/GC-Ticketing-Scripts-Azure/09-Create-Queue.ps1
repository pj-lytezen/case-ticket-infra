param(
  [string]$Prefix = "gc-tkt-prod",
  [string]$Location = "eastus",
  [string]$ServiceBusNamespaceName = ""
)

. "$PSScriptRoot\\_common.ps1"

<#
  09-Create-Queue.ps1 (Azure)

  Creates Service Bus components (queueing backbone):
  - Service Bus namespace (Standard tier)
  - Queue: jobs

  Design note:
  - Service Bus queues include a built-in Dead Letter Queue (DLQ). You don’t create a separate DLQ queue object.

  Idempotency:
  - If namespace/queue exists, script skips creation and/or updates settings.
#>

Assert-CommandExists -Name "az"

$rg = Get-ResourceGroupName -Prefix $Prefix
Ensure-ResourceGroup -Name $rg -Location $Location

$suffix = Get-DeterministicSuffix
$defaultNs = To-GlobalName -Base ("sb$Prefix$suffix") -MaxLen 50
$nsName = if ($ServiceBusNamespaceName) { $ServiceBusNamespaceName } else { $defaultNs }

try {
  $ns = Invoke-AzJson "servicebus namespace show -g $rg -n $nsName"
  Write-Host "Service Bus namespace exists: $nsName"
} catch {
  Write-Host "Creating Service Bus namespace: $nsName"
  $ns = Invoke-AzJson "servicebus namespace create -g $rg -n $nsName -l $Location --sku Standard --tags Project=SupportTicketAutomation Prefix=$Prefix"
}

$queueName = "jobs"
try {
  $q = Invoke-AzJson "servicebus queue show -g $rg --namespace-name $nsName -n $queueName"
  Write-Host "Queue exists: $queueName"
} catch {
  Write-Host "Creating queue: $queueName"
  Invoke-Expression "az servicebus queue create -g $rg --namespace-name $nsName -n $queueName --max-delivery-count 5 --enable-dead-lettering-on-message-expiration true | Out-Null" | Out-Null
}

Write-Host "Queueing complete."
Write-Host "Namespace: $nsName"
Write-Host "Queue    : $queueName (DLQ is built-in)"
Write-Host "Next: 10-Validate-Queue.ps1"
