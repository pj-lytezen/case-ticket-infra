param(
  [string]$Prefix = "gc-tkt-prod",
  [string]$Environment = "prod",
  [string]$Region = "us-east-1",
  [string]$KubernetesVersion = "1.29"
)

. "$PSScriptRoot\\_common.ps1"

<#
  11-Create-EKS.ps1

  Creates an EKS cluster and two managed node groups:
  - core (on-demand, always-on)
  - workers (spot, scales with queue depth)

  Why:
  - Matches the design goal: small always-on footprint + cheap burst compute for workers.
  - Keeps the app in private subnets.

  Idempotency:
  - Cluster and nodegroups are looked up by name; if they exist, creation is skipped.
  - IAM roles are checked by name; policies are attached idempotently.

  Important:
  - EKS creation is slow and can take 15–30 minutes.
  - This script does not deploy Kubernetes workloads; it creates the cluster foundation only.
#>

Assert-CommandExists -Name "aws"

$tags = Get-DefaultTags -Prefix $Prefix -Environment $Environment
$azs = Get-AvailabilityZones2 -Region $Region

$vpcName = "$Prefix-vpc"
$vpc = Find-VpcByNameTag -Region $Region -Name $vpcName
if (-not $vpc) { throw "Missing VPC '$vpcName'. Run 03-Create-Network.ps1 first." }
$vpcId = $vpc.VpcId

$subApp1 = Find-SubnetByNameTag -Region $Region -VpcId $vpcId -Name "$Prefix-app-$($azs[0])"
$subApp2 = Find-SubnetByNameTag -Region $Region -VpcId $vpcId -Name "$Prefix-app-$($azs[1])"
if (-not $subApp1 -or -not $subApp2) { throw "Missing app subnets. Run 03-Create-Network.ps1." }

function Ensure-IamRole {
  param([string]$RoleName,[string]$AssumeRolePolicyJson)
  try {
    $role = Invoke-AwsJson -Command "iam get-role --role-name $RoleName" -Region $Region
    Write-Host "IAM role exists: $RoleName"
    return $role.Role.Arn
  } catch { }

  $tmp = New-TemporaryFile
  Set-Content -Path $tmp.FullName -Value $AssumeRolePolicyJson -Encoding UTF8
  Write-Host "Creating IAM role: $RoleName"
  $role = Invoke-AwsJson -Command "iam create-role --role-name $RoleName --assume-role-policy-document file://$($tmp.FullName)" -Region $Region
  return $role.Role.Arn
}

function Ensure-IamRolePolicyAttachment {
  param([string]$RoleName,[string]$PolicyArn)
  # Attaching an already-attached policy is safe; IAM treats it idempotently.
  Invoke-Expression "aws iam attach-role-policy --role-name $RoleName --policy-arn $PolicyArn | Out-Null" | Out-Null
}

$clusterRoleName = "$Prefix-eks-cluster-role"
$clusterTrust = @'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "eks.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
'@
$clusterRoleArn = Ensure-IamRole -RoleName $clusterRoleName -AssumeRolePolicyJson $clusterTrust
Ensure-IamRolePolicyAttachment -RoleName $clusterRoleName -PolicyArn "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"

$nodeRoleName = "$Prefix-eks-node-role"
$nodeTrust = @'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
'@
$nodeRoleArn = Ensure-IamRole -RoleName $nodeRoleName -AssumeRolePolicyJson $nodeTrust
Ensure-IamRolePolicyAttachment -RoleName $nodeRoleName -PolicyArn "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
Ensure-IamRolePolicyAttachment -RoleName $nodeRoleName -PolicyArn "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
Ensure-IamRolePolicyAttachment -RoleName $nodeRoleName -PolicyArn "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"

# Cluster security group (explicitly created so we can reference it later, e.g., RDS ingress).
$sgName = "$Prefix-eks-cluster-sg"
$sg = Find-SgByName -Region $Region -VpcId $vpcId -GroupName $sgName
if (-not $sg) {
  Write-Host "Creating security group: $sgName"
  $sgId = (Invoke-AwsJson -Command "ec2 create-security-group --vpc-id $vpcId --group-name $sgName --description `"$Prefix EKS cluster SG`"" -Region $Region).GroupId
  Ensure-Tagged -Region $Region -ResourceId $sgId -Tags ($tags + @(@{Key='Name';Value=$sgName}))

  # Allow HTTPS from within the VPC to the cluster endpoints (conservative).
  # Tighten later by restricting to specific subnets or admin IP ranges.
  Invoke-Expression "aws ec2 authorize-security-group-ingress --region $Region --group-id $sgId --ip-permissions IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges=[{CidrIp=$($vpc.CidrBlock),Description=`"VPC internal`"}] 2>$null" | Out-Null

  $sg = Invoke-AwsJson -Command "ec2 describe-security-groups --group-ids $sgId" -Region $Region
  $sg = $sg.SecurityGroups[0]
}
Write-Host "EKS SG: $($sg.GroupId)"

$clusterName = "$Prefix-eks"
$cluster = $null
try {
  $cluster = Invoke-AwsJson -Command "eks describe-cluster --name $clusterName" -Region $Region
  Write-Host "EKS cluster exists: $clusterName status=$($cluster.cluster.status)"
} catch { }

if (-not $cluster) {
  Write-Host "Creating EKS cluster: $clusterName (version $KubernetesVersion)"

  # We place the cluster in private app subnets. Public endpoint is enabled by default in EKS;
  # you can later convert to private endpoint only if your access patterns allow it.
  $subnetIds = "$($subApp1.SubnetId),$($subApp2.SubnetId)"
  Invoke-Expression "aws eks create-cluster --region $Region --name $clusterName --kubernetes-version $KubernetesVersion --role-arn $clusterRoleArn --resources-vpc-config subnetIds=$subnetIds,securityGroupIds=$($sg.GroupId),endpointPublicAccess=true,endpointPrivateAccess=true | Out-Null" | Out-Null
}

Write-Host "Waiting for cluster to become ACTIVE..."
Invoke-Expression "aws eks wait cluster-active --region $Region --name $clusterName" | Out-Null

function Ensure-NodeGroup {
  param(
    [string]$NodeGroupName,
    [string]$CapacityType,
    [int]$MinSize,
    [int]$DesiredSize,
    [int]$MaxSize,
    [string[]]$InstanceTypes
  )

  try {
    $ng = Invoke-AwsJson -Command "eks describe-nodegroup --cluster-name $clusterName --nodegroup-name $NodeGroupName" -Region $Region
    Write-Host "Nodegroup exists: $NodeGroupName status=$($ng.nodegroup.status)"
    return
  } catch { }

  $itypes = ($InstanceTypes -join " ")
  Write-Host "Creating nodegroup: $NodeGroupName ($CapacityType) desired=$DesiredSize"

  # Note: `--subnets` expects space-separated subnet IDs (not comma-separated).
  Invoke-Expression @"
aws eks create-nodegroup --region $Region `
  --cluster-name $clusterName `
  --nodegroup-name $NodeGroupName `
  --node-role $nodeRoleArn `
  --subnets $($subApp1.SubnetId) $($subApp2.SubnetId) `
  --scaling-config minSize=$MinSize,maxSize=$MaxSize,desiredSize=$DesiredSize `
  --capacity-type $CapacityType `
  --disk-size 50 `
  --instance-types $itypes `
  --labels role=$NodeGroupName,env=$Environment `
  --tags Project=SupportTicketAutomation,Environment=$Environment,Prefix=$Prefix,Name=$Prefix-$NodeGroupName | Out-Null
"@ | Out-Null
}

Ensure-NodeGroup -NodeGroupName "core"    -CapacityType "ON_DEMAND" -MinSize 2 -DesiredSize 3 -MaxSize 4 -InstanceTypes @("t3.medium")
Ensure-NodeGroup -NodeGroupName "workers" -CapacityType "SPOT"      -MinSize 0 -DesiredSize 1 -MaxSize 5 -InstanceTypes @("t3.medium")

Write-Host "Waiting for nodegroups to become ACTIVE..."
Invoke-Expression "aws eks wait nodegroup-active --region $Region --cluster-name $clusterName --nodegroup-name core" | Out-Null
Invoke-Expression "aws eks wait nodegroup-active --region $Region --cluster-name $clusterName --nodegroup-name workers" | Out-Null

Write-Host "EKS provisioning complete."
Write-Host "Next: 12-Validate-EKS.ps1"
