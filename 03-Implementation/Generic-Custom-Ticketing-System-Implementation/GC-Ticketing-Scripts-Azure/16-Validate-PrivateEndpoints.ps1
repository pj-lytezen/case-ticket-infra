param(
  [string]$Prefix = "gc-tkt-prod"
)

. "$PSScriptRoot\\_common.ps1"

<#
  16-Validate-PrivateEndpoints.ps1 (Azure)

  Validates private endpoints created by 15-Create-PrivateEndpoints.ps1.

  Manual verification (Azure Portal):
  - Private endpoints: confirm pe-<Prefix>-blob and pe-<Prefix>-kv exist and are Approved
  - Private DNS zones: confirm A records were created for the endpoints
#>

Assert-CommandExists -Name "az"

$rg = Get-ResourceGroupName -Prefix $Prefix

$pes = Invoke-AzJson "network private-endpoint list -g $rg"
$pes | Select-Object name,provisioningState,location | Format-Table

foreach ($zone in @("privatelink.blob.core.windows.net","privatelink.vaultcore.azure.net")) {
  try {
    $records = Invoke-AzJson "network private-dns record-set a list -g $rg -z $zone"
    Write-Host "DNS zone $zone A record sets:"
    $records | Select-Object name,ttl,fqdn | Format-Table
  } catch {
    Write-Host "DNS zone not found or cannot list: $zone"
  }
}

