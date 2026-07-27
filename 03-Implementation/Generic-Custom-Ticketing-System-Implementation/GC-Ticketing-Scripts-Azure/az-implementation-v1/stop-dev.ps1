$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot "parameters.ps1")

$DeleteAcr = $true
$DeleteLogAnalytics = $true
$DeletePrivateEndpoints = $true
$DeleteServiceBus = $true
$DeletePostgres = $true
$DeleteAks = $true
$DeleteNat = $true

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-Az {
  param([Parameter(Mandatory=$true)][string]$Command)
  $raw = Invoke-Expression "az $Command"
  if ($LASTEXITCODE -ne 0) {
    throw "Azure CLI command failed (exit $LASTEXITCODE): az $Command"
  }
  return $raw
}

function Invoke-AzWithRetry {
  param(
    [Parameter(Mandatory=$true)][string]$Command,
    [int]$Retries = 3,
    [int]$DelaySeconds = 10
  )
  for ($i = 1; $i -le $Retries; $i++) {
    $raw = Invoke-Expression "az $Command"
    if ($LASTEXITCODE -eq 0) {
      return $true
    }
    if ($i -lt $Retries) {
      Start-Sleep -Seconds $DelaySeconds
    }
  }
  Write-Host "WARNING: failed after $Retries attempts: az $Command"
  return $false
}

function Test-AzResource {
  param([Parameter(Mandatory=$true)][string]$Command)
  try {
    Invoke-Expression "az $Command | Out-Null" | Out-Null
    return $true
  } catch {
    return $false
  }
}

Invoke-Az "account set --subscription $SubscriptionId" | Out-Null

$rg = $ResourceGroupName
$vnetName = "vnet-$Prefix"
$failed = @()

Write-Host "Stopping (delete preference) in subscription $SubscriptionId, resource group $rg"

if ($DeletePrivateEndpoints) {
  foreach ($pe in @("pe-$Prefix-blob","pe-$Prefix-kv")) {
    if (Test-AzResource "network private-endpoint show -g $rg -n $pe") {
      Write-Host "Deleting private endpoint: $pe"
      if (-not (Invoke-AzWithRetry "network private-endpoint delete -g $rg -n $pe")) {
        $failed += "private-endpoint:$pe"
      }
    }
  }
}

if ($DeleteAks) {
  $aksName = "aks-$Prefix"
  if (Test-AzResource "aks show -g $rg -n $aksName") {
    Write-Host "Deleting AKS: $aksName"
    if (-not (Invoke-AzWithRetry "aks delete -g $rg -n $aksName --yes" -Retries 2 -DelaySeconds 20)) {
      $failed += "aks:$aksName"
    }
  }
}

if ($DeleteAcr) {
  if (Test-AzResource "acr show -g $rg -n $AcrName") {
    Write-Host "Deleting ACR: $AcrName"
    if (-not (Invoke-AzWithRetry "acr delete -g $rg -n $AcrName --yes")) {
      $failed += "acr:$AcrName"
    }
  }
}

if ($DeleteServiceBus) {
  if (Test-AzResource "servicebus namespace show -g $rg -n $ServiceBusNamespaceName") {
    Write-Host "Deleting Service Bus namespace: $ServiceBusNamespaceName"
    if (-not (Invoke-AzWithRetry "servicebus namespace delete -g $rg -n $ServiceBusNamespaceName")) {
      $failed += "servicebus:$ServiceBusNamespaceName"
    }
  }
}

if ($DeletePostgres) {
  if (Test-AzResource "postgres flexible-server show -g $rg -n $PostgresServerName") {
    Write-Host "Deleting Postgres Flexible Server: $PostgresServerName"
    if (-not (Invoke-AzWithRetry "postgres flexible-server delete -g $rg -n $PostgresServerName --yes" -Retries 2 -DelaySeconds 20)) {
      $failed += "postgres:$PostgresServerName"
    }
  }
}

if ($DeleteNat) {
  foreach ($snet in @("snet-app","snet-aks","snet-data","snet-pe")) {
    $natId = (Invoke-Expression "az network vnet subnet show -g $rg --vnet-name $vnetName -n $snet --query natGateway.id -o tsv").Trim()
    if ($natId) {
      Write-Host "Detaching NAT from subnet: $snet"
      if (-not (Invoke-AzWithRetry "network vnet subnet update -g $rg --vnet-name $vnetName -n $snet --remove natGateway")) {
        $failed += "nat-detach:$snet"
      }
    }
  }

  $natName = "nat-$Prefix"
  if (Test-AzResource "network nat gateway show -g $rg -n $natName") {
    Write-Host "Deleting NAT Gateway: $natName"
    if (-not (Invoke-AzWithRetry "network nat gateway delete -g $rg -n $natName")) {
      $failed += "nat:$natName"
    }
  }

  $pipName = "pip-nat-$Prefix"
  if (Test-AzResource "network public-ip show -g $rg -n $pipName") {
    Write-Host "Deleting Public IP: $pipName"
    if (-not (Invoke-AzWithRetry "network public-ip delete -g $rg -n $pipName")) {
      $failed += "pip:$pipName"
    }
  }
}

if ($DeleteLogAnalytics) {
  $lawName = "law-$Prefix"
  if (Test-AzResource "monitor log-analytics workspace show -g $rg -n $lawName") {
    Write-Host "Deleting Log Analytics workspace: $lawName"
    if (-not (Invoke-AzWithRetry "monitor log-analytics workspace delete -g $rg -n $lawName --yes")) {
      $failed += "log-analytics:$lawName"
    }
  }
}

if ($failed.Count -gt 0) {
  Write-Host "Stop completed with failures:"
  $failed | ForEach-Object { Write-Host " - $_" }
} else {
  Write-Host "Stop (delete preference) complete."
}
