param(
  [string]$Prefix = "gc-tkt-prod",
  [string]$Location = "eastus",
  [string]$KeyVaultName = ""
)

. "$PSScriptRoot\\_common.ps1"

<#
  06-Validate-Security.ps1 (Azure)

  Validates Key Vault and Log Analytics workspace.

  Manual verification (Azure Portal):
  - Key Vault -> Secrets: confirm pg-admin-user and pg-admin-password exist
  - Key Vault -> Access control (IAM): confirm you can read/write secrets
  - Log Analytics workspace exists
#>

Assert-CommandExists -Name "az"

$rg = Get-ResourceGroupName -Prefix $Prefix
$suffix = Get-DeterministicSuffix
$keyVaultName = if ($KeyVaultName) { $KeyVaultName } else { (To-GlobalName -Base ("kv$Prefix$suffix") -MaxLen 24) }
$lawName = "law-$Prefix"

$kv = Invoke-AzJson "keyvault show -g $rg -n $keyVaultName"
Write-Host "Key Vault OK: $($kv.name) id=$($kv.id)"

foreach ($s in @("pg-admin-user","pg-admin-password","app-config-json")) {
  Invoke-Expression "az keyvault secret show --vault-name $keyVaultName -n $s --query id -o tsv" | Out-Null
  Write-Host "Secret OK: $s"
}

$law = Invoke-AzJson "monitor log-analytics workspace show -g $rg -n $lawName"
Write-Host "Log Analytics OK: $($law.name)"
