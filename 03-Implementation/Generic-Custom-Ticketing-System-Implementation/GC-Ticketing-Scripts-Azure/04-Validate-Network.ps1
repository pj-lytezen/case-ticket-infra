param(
  [string]$Prefix = "gc-tkt-prod",
  [string]$Location = "eastus"
)

. "$PSScriptRoot\\_common.ps1"

<#
  04-Validate-Network.ps1 (Azure)

  Validates the network created in 03-Create-Network.ps1.

  Manual verification (Azure Portal):
  - Resource group rg-<Prefix> exists and contains:
    - vnet-<Prefix> with the expected subnets
    - nat-<Prefix> and pip-nat-<Prefix>
  - VNet -> Subnets -> NAT gateway column: confirm private subnets show the NAT gateway
#>

Assert-CommandExists -Name "az"

$rg = Get-ResourceGroupName -Prefix $Prefix
$vnetName = "vnet-$Prefix"
$natName = "nat-$Prefix"

$vnet = Invoke-AzJson "network vnet show -g $rg -n $vnetName"
Write-Host "VNet OK: $($vnet.name) addressSpace=$($vnet.addressSpace.addressPrefixes -join ',')"

$subs = Invoke-AzJson "network vnet subnet list -g $rg --vnet-name $vnetName"
$subs | Select-Object name,addressPrefix,@{n='natGateway';e={$_.natGateway.id}} | Format-Table

$nat = Invoke-AzJson "network nat gateway show -g $rg -n $natName"
Write-Host "NAT OK: $($nat.name) publicIPs=$($nat.publicIpAddresses.id -join ',')"

