param(
  [string]$Prefix = "gc-tkt-prod",
  [string]$Location = "eastus",
  [string]$PostgresServerName = ""
)

. "$PSScriptRoot\\_common.ps1"

<#
  14-Validate-Postgres.ps1 (Azure)

  Validates the Postgres Flexible Server and private DNS.

  Manual verification (Azure Portal):
  - Azure Database for PostgreSQL flexible servers: confirm server exists, public access disabled
  - Private DNS zones: confirm privatelink.postgres.database.azure.com exists and is linked to vnet-<Prefix>
#>

Assert-CommandExists -Name "az"

$rg = Get-ResourceGroupName -Prefix $Prefix
$suffix = Get-DeterministicSuffix
$pgName = if ($PostgresServerName) { $PostgresServerName } else { (To-GlobalName -Base ("pg$Prefix$suffix") -MaxLen 63) }

$pg = Invoke-AzJson "postgres flexible-server show -g $rg -n $pgName"
Write-Host "Postgres OK: $($pg.name) state=$($pg.state) version=$($pg.version) fqdn=$($pg.fullyQualifiedDomainName)"

$db = Invoke-AzJson "postgres flexible-server db show -g $rg -s $pgName -d gc_ticketing"
Write-Host "Database OK: $($db.name)"
