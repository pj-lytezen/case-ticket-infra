param(
  [string]$Prefix = "gc-tkt-prod",
  [string]$Location = "eastus",
  [string]$ServiceBusNamespaceName = ""
)

. "$PSScriptRoot\\_common.ps1"

<#
  10-Validate-Queue.ps1 (Azure)

  Validates Service Bus namespace and queue.

  Manual verification (Azure Portal):
  - Service Bus -> Namespaces: confirm namespace exists
  - Queues: confirm “jobs” exists; check Dead-lettering settings
#>

Assert-CommandExists -Name "az"

$rg = Get-ResourceGroupName -Prefix $Prefix
$suffix = Get-DeterministicSuffix
$nsName = if ($ServiceBusNamespaceName) { $ServiceBusNamespaceName } else { (To-GlobalName -Base ("sb$Prefix$suffix") -MaxLen 50) }

$ns = Invoke-AzJson "servicebus namespace show -g $rg -n $nsName"
Write-Host "Namespace OK: $($ns.name)"

$q = Invoke-AzJson "servicebus queue show -g $rg --namespace-name $nsName -n jobs"
Write-Host "Queue OK: $($q.name) maxDelivery=$($q.maxDeliveryCount) deadLetterOnExpire=$($q.deadLetteringOnMessageExpiration)"
