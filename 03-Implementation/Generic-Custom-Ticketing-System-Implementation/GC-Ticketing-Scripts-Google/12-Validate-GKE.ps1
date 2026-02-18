param(
  [string]$Prefix = "gc-tkt-prod",
  [Parameter(Mandatory=$true)][string]$ProjectId,
  [string]$Region = "us-central1"
)

. "$PSScriptRoot\\_common.ps1"

<#
  12-Validate-GKE.ps1 (GCP)

  Validates the GKE cluster and node pools.

  Manual verification (GCP Console):
  - Kubernetes Engine -> Clusters: confirm cluster exists and is healthy
  - Nodes / Node pools: confirm default pool + workers pool

  Optional next step (manual):
  - Get kubectl credentials:
      gcloud container clusters get-credentials gke-<Prefix> --region <Region>
    Then:
      kubectl get nodes
#>

Assert-CommandExists -Name "gcloud"

$cluster = To-GcName -Base ("gke-$Prefix")
$c = Invoke-GcloudJson "container clusters describe $cluster --region $Region"
Write-Host "Cluster OK: $($c.name) status=$($c.status) location=$($c.location)"

$pools = Invoke-GcloudJson "container node-pools list --cluster $cluster --region $Region"
$pools | Select-Object name,status,config | Format-Table

