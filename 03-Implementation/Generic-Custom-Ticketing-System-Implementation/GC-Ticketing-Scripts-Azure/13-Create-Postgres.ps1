param(
  [string]$Prefix = "gc-tkt-prod",
  [string]$Location = "eastus",
  [string]$SkuName = "Standard_D4s_v3",
  [string]$Tier = "GeneralPurpose",
  [int]$StorageGb = 256,
  [string]$PostgresServerName = "",
  [string]$KeyVaultName = ""
)

. "$PSScriptRoot\\_common.ps1"

<#
  13-Create-Postgres.ps1 (Azure)

  Creates Azure Database for PostgreSQL Flexible Server with private access:
  - Private DNS zone: privatelink.postgres.database.azure.com
  - VNet link to vnet-<Prefix>
  - Flexible server in delegated subnet snet-pg
  - Database: gc_ticketing

  Why:
  - Matches the design: PostgreSQL is the primary system of record and powers Hybrid RAG (FTS + pgvector).
  - Private access reduces exposure and avoids public endpoints.

  Idempotency:
  - Checks for existing DNS zone/link/server/database before creating.

  Notes:
  - PostgreSQL Flexible Server private access requires a delegated subnet (created in 03-Create-Network.ps1).
#>

Assert-CommandExists -Name "az"

$rg = Get-ResourceGroupName -Prefix $Prefix
$vnetName = "vnet-$Prefix"
$pgSubnetName = "snet-pg"

$suffix = Get-DeterministicSuffix
$defaultPg = To-GlobalName -Base ("pg$Prefix$suffix") -MaxLen 63
$pgName = if ($PostgresServerName) { $PostgresServerName } else { $defaultPg }

$defaultKv = To-GlobalName -Base ("kv$Prefix$suffix") -MaxLen 24
$keyVaultName = if ($KeyVaultName) { $KeyVaultName } else { $defaultKv }
$adminUser = (Invoke-Expression "az keyvault secret show --vault-name $keyVaultName -n pg-admin-user --query value -o tsv").Trim()
$adminPass = (Invoke-Expression "az keyvault secret show --vault-name $keyVaultName -n pg-admin-password --query value -o tsv").Trim()

# Private DNS zone
$dnsZone = "privatelink.postgres.database.azure.com"
try {
  Invoke-Expression "az network private-dns zone show -g $rg -n $dnsZone | Out-Null" | Out-Null
  Write-Host "Private DNS zone exists: $dnsZone"
} catch {
  Write-Host "Creating private DNS zone: $dnsZone"
  Invoke-Expression "az network private-dns zone create -g $rg -n $dnsZone | Out-Null" | Out-Null
}
$dnsZoneId = (Invoke-Expression "az network private-dns zone show -g $rg -n $dnsZone --query id -o tsv").Trim()

# Link the zone to the VNet (required so private Postgres DNS resolves inside the VNet).
$linkName = "link-$Prefix-pg"
$vnetId = (Invoke-Expression "az network vnet show -g $rg -n $vnetName --query id -o tsv").Trim()
try {
  Invoke-Expression "az network private-dns link vnet show -g $rg -z $dnsZone -n $linkName | Out-Null" | Out-Null
  Write-Host "DNS link exists: $linkName"
} catch {
  Write-Host "Creating DNS link: $linkName"
  Invoke-Expression "az network private-dns link vnet create -g $rg -z $dnsZone -n $linkName -v $vnetId -e false | Out-Null" | Out-Null
}

$pgSubnetId = (Invoke-Expression "az network vnet subnet show -g $rg --vnet-name $vnetName -n $pgSubnetName --query id -o tsv").Trim()
if (-not $pgSubnetId) { throw "Missing delegated subnet $pgSubnetName. Run 03-Create-Network.ps1." }

try {
  $pg = Invoke-AzJson "postgres flexible-server show -g $rg -n $pgName"
  Write-Host "Postgres server exists: $pgName"
} catch {
  Write-Host "Creating Postgres Flexible Server: $pgName (private access)"

  # CLI flags for private access evolve over time; the core idea is:
  # - public access disabled
  # - deployed into delegated subnet
  # - private DNS zone used for name resolution
  try {
    Invoke-Expression @"
az postgres flexible-server create -g $rg -n $pgName -l $Location `
  --tier $Tier --sku-name $SkuName --storage-size $StorageGb `
  --admin-user $adminUser --admin-password `"$adminPass`" `
  --public-access none `
  --subnet $pgSubnetId `
  --private-dns-zone $dnsZoneId `
  --tags Project=SupportTicketAutomation Prefix=$Prefix | Out-Null
"@ | Out-Null
  } catch {
    Write-Host "ERROR: Postgres creation failed."
    Write-Host "Azure CLI flags for private access can vary by CLI version."
    Write-Host "Try this alternate form (subnet name + vnet name) manually:"
    Write-Host "  az postgres flexible-server create -g $rg -n $pgName -l $Location --tier $Tier --sku-name $SkuName --storage-size $StorageGb --admin-user $adminUser --admin-password <password> --public-access none --vnet vnet-$Prefix --subnet $pgSubnetName --private-dns-zone $dnsZone"
    throw
  }
}

# Ensure the application database exists.
$dbName = "gc_ticketing"
try {
  Invoke-Expression "az postgres flexible-server db show -g $rg -s $pgName -d $dbName | Out-Null" | Out-Null
  Write-Host "Database exists: $dbName"
} catch {
  Write-Host "Creating database: $dbName"
  Invoke-Expression "az postgres flexible-server db create -g $rg -s $pgName -d $dbName | Out-Null" | Out-Null
}

Write-Host "Postgres provisioning complete."
Write-Host "Next: 14-Validate-Postgres.ps1"
