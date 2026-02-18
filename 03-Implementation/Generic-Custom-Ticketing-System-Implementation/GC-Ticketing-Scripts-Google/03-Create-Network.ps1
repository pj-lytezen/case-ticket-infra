param(
  [string]$Prefix = "gc-tkt-prod",
  [Parameter(Mandatory=$true)][string]$ProjectId,
  [string]$Region = "us-central1"
)

. "$PSScriptRoot\\_common.ps1"

<#
  03-Create-Network.ps1 (GCP)

  Creates network foundation:
  - VPC network (custom mode)
  - Subnets:
    - subnet-gke (with secondary ranges for Pods/Services; required for VPC-native GKE)
    - subnet-data
  - Firewall rules for internal traffic
  - Cloud Router + Cloud NAT (outbound internet for private nodes)

  Design alignment:
  - Private-by-default posture (nodes/services use internal IPs; NAT handles egress).

  Idempotency:
  - Uses describe/list checks before create.
#>

Assert-CommandExists -Name "gcloud"

$netName = To-GcName -Base ("net-$Prefix")
$subGke = To-GcName -Base ("subnet-gke-$Prefix")
$subData = To-GcName -Base ("subnet-data-$Prefix")
$routerName = To-GcName -Base ("cr-$Prefix")
$natName = To-GcName -Base ("nat-$Prefix")

# VPC network (custom subnet mode).
$net = $null
try { $net = Invoke-GcloudJson "compute networks describe $netName" } catch { }
if (-not $net) {
  Write-Host "Creating VPC network: $netName"
  Invoke-Expression "gcloud compute networks create $netName --subnet-mode=custom" | Out-Null
} else {
  Write-Host "VPC exists: $netName"
}

# Subnet for GKE with secondary ranges for Pods and Services.
$gkeSubnet = $null
try { $gkeSubnet = Invoke-GcloudJson "compute networks subnets describe $subGke --region $Region" } catch { }
if (-not $gkeSubnet) {
  Write-Host "Creating subnet: $subGke"
  Invoke-Expression @"
gcloud compute networks subnets create $subGke --region $Region --network $netName `
  --range 10.20.20.0/22 `
  --secondary-range pods=10.60.0.0/16,services=10.70.0.0/20
"@ | Out-Null
} else {
  Write-Host "Subnet exists: $subGke"
}

# Subnet for data-plane private IP resources (Cloud SQL private IP uses service networking, but a data subnet is still useful).
$dataSubnet = $null
try { $dataSubnet = Invoke-GcloudJson "compute networks subnets describe $subData --region $Region" } catch { }
if (-not $dataSubnet) {
  Write-Host "Creating subnet: $subData"
  Invoke-Expression "gcloud compute networks subnets create $subData --region $Region --network $netName --range 10.20.30.0/24" | Out-Null
} else {
  Write-Host "Subnet exists: $subData"
}

# Firewall: allow internal communication within VPC CIDR ranges.
$fwInternal = To-GcName -Base ("fw-$Prefix-allow-internal")
$fw = $null
try { $fw = Invoke-GcloudJson "compute firewall-rules describe $fwInternal" } catch { }
if (-not $fw) {
  Write-Host "Creating firewall rule: $fwInternal"
  Invoke-Expression @"
gcloud compute firewall-rules create $fwInternal --network $netName `
  --allow tcp,udp,icmp `
  --source-ranges 10.20.0.0/16,10.60.0.0/16,10.70.0.0/20 `
  --description "Allow internal VPC + GKE secondary ranges"
"@ | Out-Null
} else {
  Write-Host "Firewall rule exists: $fwInternal"
}

# Cloud Router (required for Cloud NAT).
$router = $null
try { $router = Invoke-GcloudJson "compute routers describe $routerName --region $Region" } catch { }
if (-not $router) {
  Write-Host "Creating Cloud Router: $routerName"
  Invoke-Expression "gcloud compute routers create $routerName --region $Region --network $netName" | Out-Null
} else {
  Write-Host "Router exists: $routerName"
}

# Cloud NAT (outbound internet for private nodes).
$nat = $null
try { $nat = Invoke-GcloudJson "compute routers nats describe $natName --router $routerName --region $Region" } catch { }
if (-not $nat) {
  Write-Host "Creating Cloud NAT: $natName"
  Invoke-Expression @"
gcloud compute routers nats create $natName --router $routerName --region $Region `
  --nat-all-subnet-ip-ranges `
  --auto-allocate-nat-external-ips
"@ | Out-Null
} else {
  Write-Host "NAT exists: $natName"
}

Write-Host "Network foundation complete."
Write-Host "Next: 04-Validate-Network.ps1"

