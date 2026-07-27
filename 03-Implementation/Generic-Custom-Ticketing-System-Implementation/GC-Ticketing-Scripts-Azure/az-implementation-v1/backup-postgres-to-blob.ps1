Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot "parameters.ps1")

param(
  [string]$DatabaseName = "gc_ticketing",
  [string]$BackupContainer = "db-backups"
)

function Assert-CommandExists {
  param([Parameter(Mandatory=$true)][string]$Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required command '$Name' was not found on PATH."
  }
}

function Invoke-Az {
  param([Parameter(Mandatory=$true)][string]$Command)
  $raw = Invoke-Expression "az $Command"
  if ($LASTEXITCODE -ne 0) {
    throw "Azure CLI command failed (exit $LASTEXITCODE): az $Command"
  }
  return $raw
}

Assert-CommandExists -Name "az"
Assert-CommandExists -Name "pg_dump"

Invoke-Az "account set --subscription $SubscriptionId" | Out-Null

$backupDir = Join-Path $scriptRoot "backups"
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

$adminUser = (Invoke-Az "keyvault secret show --vault-name $KeyVaultName -n pg-admin-user --query value -o tsv").Trim()
$adminPass = (Invoke-Az "keyvault secret show --vault-name $KeyVaultName -n pg-admin-password --query value -o tsv").Trim()

$pgFqdn = "$PostgresServerName.postgres.database.azure.com"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupFile = "$($PostgresServerName)_$DatabaseName_$timestamp.dump"
$backupPath = Join-Path $backupDir $backupFile

Write-Host "Exporting $DatabaseName from $pgFqdn to $backupPath"
Write-Host "NOTE: For private access, run this from a network that can reach the VNet."

$env:PGPASSWORD = $adminPass
$env:PGSSLMODE = "require"

pg_dump -h $pgFqdn -U $adminUser -d $DatabaseName -F c -f $backupPath
if ($LASTEXITCODE -ne 0) {
  throw "pg_dump failed (exit $LASTEXITCODE)."
}

Write-Host "Ensuring backup container: $BackupContainer"
$exists = (Invoke-Az "storage container exists --account-name $StorageAccountName -n $BackupContainer --auth-mode login --query exists -o tsv").Trim()
if ($exists -ne "true") {
  Invoke-Az "storage container create --account-name $StorageAccountName -n $BackupContainer --auth-mode login" | Out-Null
}

Write-Host "Uploading backup to blob storage"
$blobName = "$PostgresServerName/$backupFile"
Invoke-Az "storage blob upload --account-name $StorageAccountName --container-name $BackupContainer --name $blobName --file `"$backupPath`" --auth-mode login" | Out-Null

Write-Host "Backup complete: $BackupContainer/$blobName"
