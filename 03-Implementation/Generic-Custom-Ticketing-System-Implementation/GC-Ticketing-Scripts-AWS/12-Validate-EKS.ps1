param(
  [string]$Prefix = "gc-tkt-prod",
  [string]$Region = "us-east-1"
)

. "$PSScriptRoot\\_common.ps1"

<#
  12-Validate-EKS.ps1

  Validates the EKS cluster and node groups.

  Manual verification (AWS Console):
  - EKS -> Clusters: confirm $Prefix-eks is ACTIVE
  - EKS -> Compute -> Node groups: confirm core and workers are ACTIVE
  - EC2 -> Instances: confirm instances exist in the private app subnets

  Optional next step (manual):
  - Configure kubectl:
      aws eks update-kubeconfig --region <region> --name <cluster>
    Then:
      kubectl get nodes
#>

Assert-CommandExists -Name "aws"

$clusterName = "$Prefix-eks"
$cluster = Invoke-AwsJson -Command "eks describe-cluster --name $clusterName" -Region $Region
Write-Host "Cluster: $clusterName status=$($cluster.cluster.status) version=$($cluster.cluster.version)"
Write-Host "VPC: $($cluster.cluster.resourcesVpcConfig.vpcId)"

$ngs = Invoke-AwsJson -Command "eks list-nodegroups --cluster-name $clusterName" -Region $Region
Write-Host "Nodegroups: $($ngs.nodegroups -join ', ')"

foreach ($ng in $ngs.nodegroups) {
  $d = Invoke-AwsJson -Command "eks describe-nodegroup --cluster-name $clusterName --nodegroup-name $ng" -Region $Region
  Write-Host "  $ng status=$($d.nodegroup.status) desired=$($d.nodegroup.scalingConfig.desiredSize)"
}

