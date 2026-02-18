param(
  [string]$Prefix = "gc-tkt-prod",
  [Parameter(Mandatory=$true)][string]$ProjectId,
  [string]$Region = "us-central1",
  [int]$CoreNodeCount = 3,
  [string]$MachineType = "e2-standard-2"
)

. "$PSScriptRoot\\_common.ps1"

<#
  11-Create-GKE.ps1 (GCP)

  Creates:
  - Regional GKE cluster (VPC-native) in subnet-gke
  - Core node pool (always-on)
  - Workers node pool (spot) for bursty jobs

  Design alignment:
  - “Core” pool supports always-on services (gateway/orchestrator/retrieval/evaluator/ticketing-api).
  - “Workers” pool is spot to reduce cost for ingestion/embedding/outbox jobs.

  Idempotency:
  - Cluster is created if missing.
  - Node pool creation is skipped if it exists.

  Security note:
  - This script creates a standard public-control-plane cluster for accessibility.
  - For stricter posture, evolve to private control plane + authorized networks once ops access is planned.
#>

Assert-CommandExists -Name "gcloud"

$cluster = To-GcName -Base ("gke-$Prefix")
$netName = To-GcName -Base ("net-$Prefix")
$subGke = To-GcName -Base ("subnet-gke-$Prefix")

$exists = $false
try { Invoke-Expression "gcloud container clusters describe $cluster --region $Region | Out-Null" | Out-Null; $exists = $true } catch { }

if (-not $exists) {
  Write-Host "Creating GKE cluster: $cluster"
  Invoke-Expression @"
gcloud container clusters create $cluster --region $Region `
  --network $netName --subnetwork $subGke `
  --enable-ip-alias `
  --cluster-secondary-range-name pods `
  --services-secondary-range-name services `
  --num-nodes $CoreNodeCount `
  --machine-type $MachineType `
  --enable-autoscaling --min-nodes 2 --max-nodes 4 `
  --workload-pool=$ProjectId.svc.id.goog `
  --labels=project=supportticketautomation,env=prod,prefix=$Prefix
"@ | Out-Null
} else {
  Write-Host "GKE cluster exists: $cluster"
}

# Spot worker pool
$pool = "workers"
$poolExists = $false
try { Invoke-Expression "gcloud container node-pools describe $pool --cluster $cluster --region $Region | Out-Null" | Out-Null; $poolExists = $true } catch { }
if (-not $poolExists) {
  Write-Host "Creating spot worker pool: $pool"
  Invoke-Expression @"
gcloud container node-pools create $pool --cluster $cluster --region $Region `
  --spot `
  --num-nodes 1 `
  --enable-autoscaling --min-nodes 0 --max-nodes 5 `
  --machine-type $MachineType `
  --node-labels=role=workers,env=prod
"@ | Out-Null
} else {
  Write-Host "Node pool exists: $pool"
}

Write-Host "GKE provisioning complete."
Write-Host "Next: 12-Validate-GKE.ps1"

