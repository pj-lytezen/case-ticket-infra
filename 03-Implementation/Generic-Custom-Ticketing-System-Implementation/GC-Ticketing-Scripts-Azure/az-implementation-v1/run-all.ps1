Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot "parameters.ps1")

$baseDir = (Resolve-Path (Join-Path $scriptRoot "..")).Path

function Invoke-Step {
  param([string]$Path, [hashtable]$Parameters)
  Write-Host "Running $Path"
  & $Path @Parameters
}

Invoke-Step -Path (Join-Path $baseDir "01-Context.ps1") -Parameters @{ Prefix = $Prefix; Location = $Location }
Invoke-Step -Path (Join-Path $baseDir "02-Validate-Context.ps1") -Parameters @{ Prefix = $Prefix; Location = $Location }

Invoke-Step -Path (Join-Path $baseDir "03-Create-Network.ps1") -Parameters @{ Prefix = $Prefix; Location = $Location }
Invoke-Step -Path (Join-Path $baseDir "04-Validate-Network.ps1") -Parameters @{ Prefix = $Prefix; Location = $Location }

Invoke-Step -Path (Join-Path $baseDir "05-Create-Security.ps1") -Parameters @{ Prefix = $Prefix; Location = $Location; KeyVaultName = $KeyVaultName }
Invoke-Step -Path (Join-Path $baseDir "06-Validate-Security.ps1") -Parameters @{ Prefix = $Prefix; Location = $Location; KeyVaultName = $KeyVaultName }

Invoke-Step -Path (Join-Path $baseDir "07-Create-Storage.ps1") -Parameters @{ Prefix = $Prefix; Location = $Location; StorageAccountName = $StorageAccountName }
Invoke-Step -Path (Join-Path $baseDir "08-Validate-Storage.ps1") -Parameters @{ Prefix = $Prefix; Location = $Location; StorageAccountName = $StorageAccountName }

Invoke-Step -Path (Join-Path $baseDir "09-Create-Queue.ps1") -Parameters @{ Prefix = $Prefix; Location = $Location; ServiceBusNamespaceName = $ServiceBusNamespaceName }
Invoke-Step -Path (Join-Path $baseDir "10-Validate-Queue.ps1") -Parameters @{ Prefix = $Prefix; Location = $Location; ServiceBusNamespaceName = $ServiceBusNamespaceName }

Invoke-Step -Path (Join-Path $baseDir "11-Create-AKS.ps1") -Parameters @{ Prefix = $Prefix; Location = $Location; AcrName = $AcrName; CoreNodeVmSize = $CoreNodeVmSize }
Invoke-Step -Path (Join-Path $baseDir "12-Validate-AKS.ps1") -Parameters @{ Prefix = $Prefix; AcrName = $AcrName }

Invoke-Step -Path (Join-Path $baseDir "13-Create-Postgres.ps1") -Parameters @{ Prefix = $Prefix; Location = $Location; PostgresServerName = $PostgresServerName; KeyVaultName = $KeyVaultName }
Invoke-Step -Path (Join-Path $baseDir "14-Validate-Postgres.ps1") -Parameters @{ Prefix = $Prefix; Location = $Location; PostgresServerName = $PostgresServerName }

Invoke-Step -Path (Join-Path $baseDir "15-Create-PrivateEndpoints.ps1") -Parameters @{ Prefix = $Prefix; Location = $Location; StorageAccountName = $StorageAccountName; KeyVaultName = $KeyVaultName }
Invoke-Step -Path (Join-Path $baseDir "16-Validate-PrivateEndpoints.ps1") -Parameters @{ Prefix = $Prefix }
