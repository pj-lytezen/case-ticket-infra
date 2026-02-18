param(
  [string]$Prefix = "gc-tkt-prod",
  [string]$AcrName = ""
)

. "$PSScriptRoot\\_common.ps1"

<#
  12-Validate-AKS.ps1 (Azure)

  Validates AKS + ACR.

  Manual verification (Azure Portal):
  - Kubernetes services -> aks-<Prefix>: confirm provisioningState Succeeded
  - Node pools: confirm default + workers pool
  - Container Registries: confirm acr<...> exists

  Optional next step (manual):
  - Configure kubectl:
      az aks get-credentials -g rg-<Prefix> -n aks-<Prefix>
    Then:
      kubectl get nodes
#>

Assert-CommandExists -Name "az"

$rg = Get-ResourceGroupName -Prefix $Prefix
$suffix = Get-DeterministicSuffix
$acrName = if ($AcrName) { $AcrName } else { (To-GlobalName -Base ("acr$Prefix$suffix") -MaxLen 50) }
$aksName = "aks-$Prefix"

$aks = Invoke-AzJson "aks show -g $rg -n $aksName"
Write-Host "AKS OK: $($aks.name) state=$($aks.provisioningState) kubernetesVersion=$($aks.kubernetesVersion)"

$pools = Invoke-AzJson "aks nodepool list -g $rg --cluster-name $aksName"
$pools | Select-Object name,mode,osType,vmSize,count,enableAutoScaling,scaleSetPriority | Format-Table

$acr = Invoke-AzJson "acr show -g $rg -n $acrName"
Write-Host "ACR OK: $($acr.name) sku=$($acr.sku.name)"
