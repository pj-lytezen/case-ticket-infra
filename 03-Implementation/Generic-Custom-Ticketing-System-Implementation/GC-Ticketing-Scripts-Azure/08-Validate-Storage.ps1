param(
  [string]$Prefix = "gc-tkt-prod",
  [string]$Location = "eastus",
  [string]$StorageAccountName = ""
)

. "$PSScriptRoot\\_common.ps1"

<#
  08-Validate-Storage.ps1 (Azure)

  Validates the storage account and containers.

  Manual verification (Azure Portal):
  - Storage account -> Containers: confirm docs/attachments/audit exist
  - Storage account -> Configuration: confirm “Allow Blob public access” is disabled
#>

Assert-CommandExists -Name "az"

$rg = Get-ResourceGroupName -Prefix $Prefix
$suffix = Get-DeterministicSuffix
$storageName = if ($StorageAccountName) { $StorageAccountName } else { (To-GlobalName -Base ("st$Prefix$suffix") -MaxLen 24) }

$st = Invoke-AzJson "storage account show -g $rg -n $storageName"
Write-Host "Storage OK: $($st.name) sku=$($st.sku.name)"

foreach ($c in @("docs","attachments","audit")) {
  $exists = (Invoke-Expression "az storage container exists --account-name $storageName -n $c --auth-mode login --query exists -o tsv").Trim()
  Write-Host "Container $c exists=$exists"
}
