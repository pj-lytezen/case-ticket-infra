param(
  [string]$Prefix = "gc-tkt-prod",
  [Parameter(Mandatory=$true)][string]$ProjectId,
  [string]$Region = "us-central1"
)

. "$PSScriptRoot\\_common.ps1"

<#
  14-Validate-CloudSQL.ps1 (GCP)

  Validates Cloud SQL instance and database.

  Manual verification (GCP Console):
  - SQL -> Instances: confirm instance exists, has Private IP, and HA status matches your choice
  - SQL -> Databases: confirm gc_ticketing exists
#>

Assert-CommandExists -Name "gcloud"

$sqlInstance = To-GcName -Base ("sql-$Prefix")
$i = Invoke-GcloudJson "sql instances describe $sqlInstance"
Write-Host "Instance OK: $($i.name) state=$($i.state) region=$($i.region) tier=$($i.settings.tier)"
Write-Host "Private IP: $($i.ipAddresses | Where-Object { $_.type -eq 'PRIVATE' } | Select-Object -First 1 -ExpandProperty ipAddress)"

Invoke-Expression "gcloud sql databases describe gc_ticketing --instance $sqlInstance | Out-Null" | Out-Null
Write-Host "Database OK: gc_ticketing"

