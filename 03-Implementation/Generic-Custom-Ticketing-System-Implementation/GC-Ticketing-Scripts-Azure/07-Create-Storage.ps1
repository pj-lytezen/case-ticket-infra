param(
  [string]$Prefix = "gc-tkt-prod",
  [string]$Location = "eastus",
  [string]$Sku = "Standard_LRS",
  [string]$StorageAccountName = ""
)

. "$PSScriptRoot\\_common.ps1"

<#
  07-Create-Storage.ps1 (Azure)

  Creates:
  - Storage account (object storage equivalent to S3 for documents/attachments)
  - Blob containers: docs, attachments, audit

  Idempotency:
  - Storage account name is deterministic from Prefix+Subscription suffix.
  - If it exists, containers are ensured.

  Cost note:
  - Standard_LRS is the cost-effective default.
  - For stricter durability/availability, consider ZRS or GRS (higher cost).
#>

Assert-CommandExists -Name "az"

$rg = Get-ResourceGroupName -Prefix $Prefix
Ensure-ResourceGroup -Name $rg -Location $Location

$suffix = Get-DeterministicSuffix
$defaultName = To-GlobalName -Base ("st$Prefix$suffix") -MaxLen 24
$storageName = if ($StorageAccountName) { $StorageAccountName } else { $defaultName }

try {
  $st = Invoke-AzJson "storage account show -g $rg -n $storageName"
  Write-Host "Storage account exists: $storageName"
} catch {
  Write-Host "Creating storage account: $storageName ($Sku)"
  Invoke-Expression "az storage account create -g $rg -n $storageName -l $Location --kind StorageV2 --sku $Sku --min-tls-version TLS1_2 --https-only true --allow-blob-public-access false --tags Project=SupportTicketAutomation Prefix=$Prefix | Out-Null" | Out-Null
}

# Create containers (requires an auth mode; simplest is login-based).
foreach ($c in @("docs","attachments","audit")) {
  $exists = $false
  try {
    $exists = (Invoke-Expression "az storage container exists --account-name $storageName -n $c --auth-mode login --query exists -o tsv").Trim() -eq "true"
  } catch { }

  if (-not $exists) {
    Write-Host "Creating container: $c"
    Invoke-Expression "az storage container create --account-name $storageName -n $c --auth-mode login | Out-Null" | Out-Null
  } else {
    Write-Host "Container exists: $c"
  }
}

Write-Host "Storage complete."
Write-Host "Storage account: $storageName"
Write-Host "Next: 08-Validate-Storage.ps1"
