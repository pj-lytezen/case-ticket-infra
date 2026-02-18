param(
  [string]$Prefix = "gc-tkt-prod",
  [string]$Location = "eastus",
  [string]$StorageAccountName = "",
  [string]$KeyVaultName = ""
)

. "$PSScriptRoot\\_common.ps1"

<#
  15-Create-PrivateEndpoints.ps1 (Azure)

  Creates private endpoints (optional but recommended) to reduce NAT usage and improve security:
  - Storage account (Blob)
  - Key Vault

  Why:
  - Private endpoints keep traffic to Storage/Key Vault on Azure’s backbone and avoid NAT gateway data processing for those flows.
  - This is one of the highest-impact cost and security optimizations for private subnet designs.

  Idempotency:
  - Checks existing private endpoints by name.
  - Ensures private DNS zones exist and are linked to the VNet.
#>

Assert-CommandExists -Name "az"

$rg = Get-ResourceGroupName -Prefix $Prefix
$vnetName = "vnet-$Prefix"
$peSubnetName = "snet-pe"

$suffix = Get-DeterministicSuffix
$storageName = if ($StorageAccountName) { $StorageAccountName } else { (To-GlobalName -Base ("st$Prefix$suffix") -MaxLen 24) }
$kvName = if ($KeyVaultName) { $KeyVaultName } else { (To-GlobalName -Base ("kv$Prefix$suffix") -MaxLen 24) }

$vnetId = (Invoke-Expression "az network vnet show -g $rg -n $vnetName --query id -o tsv").Trim()
$peSubnetId = (Invoke-Expression "az network vnet subnet show -g $rg --vnet-name $vnetName -n $peSubnetName --query id -o tsv").Trim()
if (-not $peSubnetId) { throw "Missing snet-pe. Run 03-Create-Network.ps1." }

function Ensure-PrivateDnsZoneAndLink {
  param([string]$ZoneName,[string]$LinkName)
  try { Invoke-Expression "az network private-dns zone show -g $rg -n $ZoneName | Out-Null" | Out-Null } catch {
    Write-Host "Creating Private DNS zone: $ZoneName"
    Invoke-Expression "az network private-dns zone create -g $rg -n $ZoneName | Out-Null" | Out-Null
  }
  try { Invoke-Expression "az network private-dns link vnet show -g $rg -z $ZoneName -n $LinkName | Out-Null" | Out-Null } catch {
    Write-Host "Linking DNS zone to VNet: $ZoneName"
    Invoke-Expression "az network private-dns link vnet create -g $rg -z $ZoneName -n $LinkName -v $vnetId -e false | Out-Null" | Out-Null
  }
}

function Ensure-PrivateEndpoint {
  param(
    [string]$PeName,
    [string]$TargetResourceId,
    [string]$GroupId,
    [string]$DnsZoneName
  )
  try {
    Invoke-Expression "az network private-endpoint show -g $rg -n $PeName | Out-Null" | Out-Null
    Write-Host "Private endpoint exists: $PeName"
    return
  } catch { }

  Write-Host "Creating private endpoint: $PeName (groupId=$GroupId)"
  Invoke-Expression @"
az network private-endpoint create -g $rg -n $PeName -l $Location `
  --subnet $peSubnetId `
  --private-connection-resource-id $TargetResourceId `
  --group-id $GroupId `
  --connection-name $PeName | Out-Null
"@ | Out-Null

  # DNS zone group to auto-register DNS records.
  $zoneGroupName = "zg-$PeName"
  try {
    Invoke-Expression "az network private-endpoint dns-zone-group show -g $rg --endpoint-name $PeName -n $zoneGroupName | Out-Null" | Out-Null
  } catch {
    Write-Host "Creating DNS zone group for $PeName"
    $zoneId = (Invoke-Expression "az network private-dns zone show -g $rg -n $DnsZoneName --query id -o tsv").Trim()
    Invoke-Expression @"
az network private-endpoint dns-zone-group create -g $rg --endpoint-name $PeName -n $zoneGroupName `
  --private-dns-zone $zoneId --zone-name $DnsZoneName | Out-Null
"@ | Out-Null
  }
}

# Storage (Blob) private endpoint
$blobZone = "privatelink.blob.core.windows.net"
Ensure-PrivateDnsZoneAndLink -ZoneName $blobZone -LinkName "link-$Prefix-blob"
$stId = (Invoke-Expression "az storage account show -g $rg -n $storageName --query id -o tsv").Trim()
Ensure-PrivateEndpoint -PeName "pe-$Prefix-blob" -TargetResourceId $stId -GroupId "blob" -DnsZoneName $blobZone

# Key Vault private endpoint
$kvZone = "privatelink.vaultcore.azure.net"
Ensure-PrivateDnsZoneAndLink -ZoneName $kvZone -LinkName "link-$Prefix-kv"
$kvId = (Invoke-Expression "az keyvault show -g $rg -n $kvName --query id -o tsv").Trim()
Ensure-PrivateEndpoint -PeName "pe-$Prefix-kv" -TargetResourceId $kvId -GroupId "vault" -DnsZoneName $kvZone

Write-Host "Private endpoints complete."
Write-Host "Next: 16-Validate-PrivateEndpoints.ps1"
