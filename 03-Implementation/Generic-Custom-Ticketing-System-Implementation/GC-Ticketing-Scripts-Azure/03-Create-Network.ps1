param(
  [string]$Prefix = "gc-tkt-prod",
  [string]$Location = "eastus",
  [string]$VpcCidr = "10.20.0.0/16"
)

. "$PSScriptRoot\\_common.ps1"

<#
  03-Create-Network.ps1 (Azure)

  Creates the Azure network foundation:
  - Resource group: rg-<Prefix>
  - VNet: vnet-<Prefix> (10.20.0.0/16 by default)
  - Subnets:
    - snet-public  (ingress/NAT public IP lives “outside” the VNet but this subnet can host public-facing components)
    - snet-app     (private app services, future VM/containers if desired)
    - snet-aks     (AKS nodes)
    - snet-data    (data plane components)
    - snet-pg      (delegated to PostgreSQL Flexible Server for private access)
    - snet-pe      (private endpoints for Storage/KeyVault)
  - NAT Gateway + Public IP: for private subnet egress (patching, LLM API calls, etc.)

  Why:
  - Mirrors the design’s “private-by-default” posture.
  - Dedicated subnets make private endpoints and delegated services cleaner and easier to audit.

  Idempotency:
  - Checks existence of RG/VNet/subnets/NAT and only creates missing resources.
#>

Assert-CommandExists -Name "az"

$rg = Get-ResourceGroupName -Prefix $Prefix
Ensure-ResourceGroup -Name $rg -Location $Location

$vnetName = "vnet-$Prefix"

try {
  $vnet = Invoke-AzJson "network vnet show -g $rg -n $vnetName"
  Write-Host "VNet exists: $vnetName"
} catch {
  Write-Host "Creating VNet: $vnetName ($VpcCidr)"
  $vnet = Invoke-AzJson "network vnet create -g $rg -n $vnetName --address-prefixes $VpcCidr --tags Project=SupportTicketAutomation Environment=prod Prefix=$Prefix"
  $vnet = $vnet.newVNet
}

function Ensure-Subnet {
  param(
    [string]$Name,
    [string]$PrefixCidr,
    [string]$Delegation = $null
  )
  try {
    $s = Invoke-AzJson "network vnet subnet show -g $rg --vnet-name $vnetName -n $Name"
    Write-Host "Subnet exists: $Name"
    return $s
  } catch { }

  Write-Host "Creating subnet: $Name ($PrefixCidr)"
  $cmd = "network vnet subnet create -g $rg --vnet-name $vnetName -n $Name --address-prefixes $PrefixCidr"
  if ($Delegation) {
    # Delegation is required for Postgres Flexible Server private access mode.
    $cmd += " --delegations $Delegation"
  }
  (Invoke-AzJson $cmd).id | Out-Null
  return (Invoke-AzJson "network vnet subnet show -g $rg --vnet-name $vnetName -n $Name")
}

# Address plan (simple, predictable; adjust as needed).
Ensure-Subnet -Name "snet-public" -PrefixCidr "10.20.0.0/24"  | Out-Null
Ensure-Subnet -Name "snet-app"    -PrefixCidr "10.20.10.0/24" | Out-Null
Ensure-Subnet -Name "snet-aks"    -PrefixCidr "10.20.20.0/22" | Out-Null
Ensure-Subnet -Name "snet-data"   -PrefixCidr "10.20.30.0/24" | Out-Null
Ensure-Subnet -Name "snet-pe"     -PrefixCidr "10.20.50.0/24" | Out-Null
Ensure-Subnet -Name "snet-pg"     -PrefixCidr "10.20.40.0/24" -Delegation "Microsoft.DBforPostgreSQL/flexibleServers" | Out-Null

# NAT Gateway (to provide controlled outbound internet for private subnets).
$natName = "nat-$Prefix"
$pipName = "pip-nat-$Prefix"

try {
  $nat = Invoke-AzJson "network nat gateway show -g $rg -n $natName"
  Write-Host "NAT Gateway exists: $natName"
} catch {
  # Public IP for NAT
  try {
    $pip = Invoke-AzJson "network public-ip show -g $rg -n $pipName"
    Write-Host "Public IP exists: $pipName"
  } catch {
    Write-Host "Creating Public IP for NAT: $pipName"
    $pip = Invoke-AzJson "network public-ip create -g $rg -n $pipName --sku Standard --allocation-method Static --tags Project=SupportTicketAutomation Prefix=$Prefix"
    $pip = $pip.publicIp
  }

  Write-Host "Creating NAT Gateway: $natName"
  $nat = Invoke-AzJson "network nat gateway create -g $rg -n $natName --public-ip-addresses $pipName --idle-timeout 10 --tags Project=SupportTicketAutomation Prefix=$Prefix"
  $nat = $nat.natGateway
}

# Associate NAT to private subnets that need outbound connectivity.
foreach ($snet in @("snet-app","snet-aks","snet-data","snet-pe")) {
  $s = Invoke-AzJson "network vnet subnet show -g $rg --vnet-name $vnetName -n $snet"
  if ($s.natGateway -and $s.natGateway.id) {
    Write-Host "NAT already associated to $snet"
    continue
  }
  Write-Host "Associating NAT to subnet: $snet"
  Invoke-Expression "az network vnet subnet update -g $rg --vnet-name $vnetName -n $snet --nat-gateway $natName | Out-Null" | Out-Null
}

Write-Host "Network foundation complete."
Write-Host "Next: 04-Validate-Network.ps1"

