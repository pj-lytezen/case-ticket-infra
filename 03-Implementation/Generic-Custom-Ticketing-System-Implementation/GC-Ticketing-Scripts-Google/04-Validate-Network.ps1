param(
  [string]$Prefix = "gc-tkt-prod",
  [Parameter(Mandatory=$true)][string]$ProjectId,
  [string]$Region = "us-central1"
)

. "$PSScriptRoot\\_common.ps1"

<#
  04-Validate-Network.ps1 (GCP)

  Validates network resources created by 03-Create-Network.ps1.

  Manual verification (GCP Console):
  - VPC network -> VPC networks: confirm net-<Prefix> exists
  - VPC network -> Subnets: confirm subnet-gke and subnet-data exist with correct ranges
  - Network services -> Cloud NAT: confirm NAT is configured and attached to Cloud Router
#>

Assert-CommandExists -Name "gcloud"

$netName = To-GcName -Base ("net-$Prefix")
$subGke = To-GcName -Base ("subnet-gke-$Prefix")
$subData = To-GcName -Base ("subnet-data-$Prefix")
$routerName = To-GcName -Base ("cr-$Prefix")
$natName = To-GcName -Base ("nat-$Prefix")

$net = Invoke-GcloudJson "compute networks describe $netName"
Write-Host "VPC OK: $($net.name)"

$sg = Invoke-GcloudJson "compute networks subnets describe $subGke --region $Region"
Write-Host "Subnet GKE OK: $($sg.name) primary=$($sg.ipCidrRange)"

$sd = Invoke-GcloudJson "compute networks subnets describe $subData --region $Region"
Write-Host "Subnet Data OK: $($sd.name) primary=$($sd.ipCidrRange)"

$router = Invoke-GcloudJson "compute routers describe $routerName --region $Region"
Write-Host "Router OK: $($router.name)"

$nat = Invoke-GcloudJson "compute routers nats describe $natName --router $routerName --region $Region"
Write-Host "NAT OK: $($nat.name)"

