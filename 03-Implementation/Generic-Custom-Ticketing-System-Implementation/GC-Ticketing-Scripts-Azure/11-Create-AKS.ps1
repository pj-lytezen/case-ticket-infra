param(
  [string]$Prefix = "gc-tkt-prod",
  [string]$Location = "eastus",
  [int]$CoreNodeCount = 3,
  [string]$CoreNodeVmSize = "Standard_D2s_v5",
  [string]$AcrName = ""
)

. "$PSScriptRoot\\_common.ps1"

<#
  11-Create-AKS.ps1 (Azure)

  Creates:
  - ACR (container registry)
  - AKS cluster in the private AKS subnet with autoscaler enabled
  - Spot node pool for workers (cheap burst capacity)
  - Monitoring addon wired to Log Analytics workspace (created in 05)

  Design alignment:
  - “Core” is always-on; “workers” are spot and can scale with queue depth.

  Idempotency:
  - Checks if ACR/AKS exist; if they do, skips creation.
#>

Assert-CommandExists -Name "az"

$rg = Get-ResourceGroupName -Prefix $Prefix
$vnetName = "vnet-$Prefix"
$aksSubnetName = "snet-aks"
$aksName = "aks-$Prefix"
$lawName = "law-$Prefix"

$suffix = Get-DeterministicSuffix
$defaultAcr = To-GlobalName -Base ("acr$Prefix$suffix") -MaxLen 50
$acrName = if ($AcrName) { $AcrName } else { $defaultAcr }

# ACR
try {
  $acr = Invoke-AzJson "acr show -g $rg -n $acrName"
  Write-Host "ACR exists: $acrName"
} catch {
  Write-Host "Creating ACR: $acrName"
  Invoke-Expression "az acr create -g $rg -n $acrName --sku Standard --admin-enabled false --tags Project=SupportTicketAutomation Prefix=$Prefix | Out-Null" | Out-Null
}

# AKS subnet id
$aksSubnetId = (Invoke-Expression "az network vnet subnet show -g $rg --vnet-name $vnetName -n $aksSubnetName --query id -o tsv").Trim()
if (-not $aksSubnetId) { throw "Missing AKS subnet. Run 03-Create-Network.ps1 first." }

# Log Analytics workspace id (for monitoring addon)
$lawId = (Invoke-Expression "az monitor log-analytics workspace show -g $rg -n $lawName --query id -o tsv").Trim()

try {
  $aks = Invoke-AzJson "aks show -g $rg -n $aksName"
  Write-Host "AKS exists: $aksName"
} catch {
  Write-Host "Creating AKS cluster: $aksName"

  Invoke-Expression @"
az aks create -g $rg -n $aksName -l $Location `
  --enable-managed-identity `
  --node-count $CoreNodeCount `
  --node-vm-size $CoreNodeVmSize `
  --enable-cluster-autoscaler --min-count 2 --max-count 4 `
  --network-plugin azure `
  --vnet-subnet-id $aksSubnetId `
  --attach-acr $acrName `
  --enable-addons monitoring `
  --workspace-resource-id $lawId `
  --tags Project=SupportTicketAutomation Prefix=$Prefix | Out-Null
"@ | Out-Null
}

# Spot node pool for workers (idempotent: check if exists)
$poolName = "workers"
$exists = $false
try {
  Invoke-Expression "az aks nodepool show -g $rg --cluster-name $aksName -n $poolName | Out-Null" | Out-Null
  $exists = $true
} catch { }

if (-not $exists) {
  Write-Host "Adding spot nodepool: $poolName"
  Invoke-Expression @"
az aks nodepool add -g $rg --cluster-name $aksName -n $poolName `
  --node-count 1 `
  --enable-cluster-autoscaler --min-count 0 --max-count 5 `
  --priority Spot --eviction-policy Delete --spot-max-price -1 `
  --node-vm-size $CoreNodeVmSize `
  --labels role=workers env=prod | Out-Null
"@ | Out-Null
} else {
  Write-Host "Nodepool exists: $poolName"
}

Write-Host "AKS provisioning complete."
Write-Host "Next: 12-Validate-AKS.ps1"
