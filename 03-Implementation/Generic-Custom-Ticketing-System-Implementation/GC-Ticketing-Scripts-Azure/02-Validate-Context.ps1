param(
  [string]$Prefix = "gc-tkt-prod",
  [string]$Location = "eastus"
)

. "$PSScriptRoot\\_common.ps1"

<#
  02-Validate-Context.ps1 (Azure)

  Validation companion for 01-Context.ps1.

  Manual verification (Azure Portal):
  - Confirm the active subscription is correct (top bar -> Directory + subscription filter).
  - Confirm you have role assignments to create: VNets, AKS, Postgres Flexible Server, Storage, Service Bus, Key Vault.
#>

Assert-CommandExists -Name "az"

$subId = Get-AzSubscriptionId
Write-Host "OK: Azure CLI active subscription id = $subId"
Write-Host "Reminder: run 'az account set --subscription <id>' if you need to switch."

