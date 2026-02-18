Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
  Common helpers for Azure provisioning scripts (Azure CLI based).

  Import pattern:
    . "$PSScriptRoot\\_common.ps1"

  Why:
  - Ensures idempotency (get-or-create semantics).
  - Provides consistent JSON parsing for `az ... -o json`.
#>

function Assert-CommandExists {
  param([Parameter(Mandatory=$true)][string]$Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required command '$Name' was not found on PATH. Install it and retry."
  }
}

function Invoke-AzJson {
  param([Parameter(Mandatory=$true)][string]$Command)
  $raw = Invoke-Expression "az $Command -o json"
  if (-not $raw) { return $null }
  return $raw | ConvertFrom-Json
}

function Get-AzSubscriptionId {
  # Returns the current active subscription id (GUID) as a string.
  (Invoke-Expression "az account show --query id -o tsv").Trim()
}

function Get-DeterministicSuffix {
  <#
    Many Azure resource names must be globally unique (Key Vault, Storage, ACR, Postgres server DNS).
    To keep scripts idempotent while reducing collisions, we derive a stable suffix from the subscription id.
  #>
  $subId = Get-AzSubscriptionId
  ($subId -replace '-', '').Substring(0, 6).ToLower()
}

function To-GlobalName {
  <#
    Normalizes a prefix into a safe Azure global name:
    - lowercase
    - alphanumeric only
    - truncated to a max length
  #>
  param([string]$Base,[int]$MaxLen)
  $clean = ($Base.ToLower() -replace '[^a-z0-9]', '')
  if ($clean.Length -gt $MaxLen) { return $clean.Substring(0, $MaxLen) }
  return $clean
}

function Get-ResourceGroupName {
  param([Parameter(Mandatory=$true)][string]$Prefix)
  "rg-$Prefix"
}

function Ensure-ResourceGroup {
  param([string]$Name,[string]$Location)
  $exists = (Invoke-Expression "az group exists --name $Name") | ConvertFrom-Json
  if ($exists -eq $true) {
    Write-Host "Resource group exists: $Name"
    return
  }
  Write-Host "Creating resource group: $Name ($Location)"
  Invoke-Expression "az group create --name $Name --location $Location --tags Project=SupportTicketAutomation" | Out-Null
}

function Ensure-Tag {
  param([string]$ResourceId,[hashtable]$Tags)
  # Azure supports tagging most resources; updating tags is idempotent.
  $tagArgs = $Tags.Keys | ForEach-Object { "$_=$($Tags[$_])" }
  Invoke-Expression "az resource tag --ids $ResourceId --tags $($tagArgs -join ' ')" | Out-Null
}
