param(
  [string]$Prefix = "gc-tkt-prod",
  [Parameter(Mandatory=$true)][string]$ProjectId,
  [string]$Region = "us-central1",
  [string]$Tier = "db-custom-2-7680",
  [int]$StorageGb = 256,
  [bool]$HighAvailability = $true
)

. "$PSScriptRoot\\_common.ps1"

<#
  13-Create-CloudSQL.ps1 (GCP)

  Creates Cloud SQL for PostgreSQL with private IP:
  - Reserves a peering range for Service Networking
  - Connects Service Networking to the VPC (required for private IP)
  - Creates the Cloud SQL instance (regional HA optional)
  - Creates database: gc_ticketing
  - Creates application user: gc_admin

  Why:
  - Matches the design: PostgreSQL is the primary store and supports Hybrid RAG indices.

  Idempotency:
  - Checks and reuses existing peering range, connection, instance, database, and user.

  Important:
  - Private IP Cloud SQL requires `servicenetworking.googleapis.com` API enabled (done in 01-Context.ps1).
#>

Assert-CommandExists -Name "gcloud"

$netName = To-GcName -Base ("net-$Prefix")
$rangeName = To-GcName -Base ("psa-$Prefix")
$sqlInstance = To-GcName -Base ("sql-$Prefix")

# Reserve an internal IP range for private service access (PSA).
$rangeExists = $false
try { Invoke-Expression "gcloud compute addresses describe $rangeName --global | Out-Null" | Out-Null; $rangeExists = $true } catch { }
if (-not $rangeExists) {
  Write-Host "Reserving global address range for Service Networking: $rangeName"
  Invoke-Expression @"
gcloud compute addresses create $rangeName --global `
  --purpose=VPC_PEERING `
  --prefix-length=16 `
  --network=$netName `
  --description="PSA range for Cloud SQL private IP"
"@ | Out-Null
} else {
  Write-Host "PSA range exists: $rangeName"
}

# Connect service networking (idempotent: reconnect is safe if already connected).
Write-Host "Ensuring Service Networking connection exists..."
try {
  Invoke-Expression "gcloud services vpc-peerings connect --service=servicenetworking.googleapis.com --ranges=$rangeName --network=$netName | Out-Null" | Out-Null
} catch {
  # If already connected, the command may error; we accept that as “already done”.
  Write-Host "Service Networking connect returned an error (often means it already exists). Continuing..."
}

# Get DB password from Secret Manager.
$pwdSecret = To-GcName -Base "$Prefix-sql-password"
$dbPass = (Invoke-Expression "gcloud secrets versions access latest --secret=$pwdSecret").Trim()

# Create Cloud SQL instance if missing.
$sqlExists = $false
try { Invoke-Expression "gcloud sql instances describe $sqlInstance | Out-Null" | Out-Null; $sqlExists = $true } catch { }
if (-not $sqlExists) {
  $ha = if ($HighAvailability) { "REGIONAL" } else { "ZONAL" }
  Write-Host "Creating Cloud SQL instance: $sqlInstance (availability=$ha)"
  Invoke-Expression @"
gcloud sql instances create $sqlInstance --database-version=POSTGRES_15 --region=$Region `
  --network=projects/$ProjectId/global/networks/$netName `
  --no-assign-ip `
  --tier=$Tier `
  --storage-size=$StorageGb `
  --availability-type=$ha `
  --backup-start-time=03:00 `
  --root-password="$dbPass"
"@ | Out-Null
} else {
  Write-Host "Cloud SQL instance exists: $sqlInstance"
}

# Ensure database exists.
$dbName = "gc_ticketing"
$dbExists = $false
try { Invoke-Expression "gcloud sql databases describe $dbName --instance $sqlInstance | Out-Null" | Out-Null; $dbExists = $true } catch { }
if (-not $dbExists) {
  Write-Host "Creating database: $dbName"
  Invoke-Expression "gcloud sql databases create $dbName --instance $sqlInstance" | Out-Null
} else {
  Write-Host "Database exists: $dbName"
}

# Ensure application user exists.
$user = "gc_admin"
$users = @()
try { $users = Invoke-GcloudJson "sql users list --instance $sqlInstance" } catch { $users = @() }
$userExists = ($users | Where-Object { $_.name -eq $user } | Select-Object -First 1) -ne $null
if (-not $userExists) {
  Write-Host "Creating DB user: $user"
  Invoke-Expression "gcloud sql users create $user --instance $sqlInstance --password `"$dbPass`"" | Out-Null
} else {
  Write-Host "DB user exists: $user"
}

Write-Host "Cloud SQL provisioning complete."
Write-Host "Next: 14-Validate-CloudSQL.ps1"
