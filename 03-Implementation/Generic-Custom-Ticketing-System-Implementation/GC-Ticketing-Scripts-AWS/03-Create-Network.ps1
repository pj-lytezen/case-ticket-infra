param(
  [string]$Prefix = "gc-tkt-prod",
  [string]$Environment = "prod",
  [string]$Region = "us-east-1",
  [string]$VpcCidr = "10.20.0.0/16"
)

. "$PSScriptRoot\\_common.ps1"

<#
  03-Create-Network.ps1

  Creates the AWS network foundation for the system:
  - VPC with DNS enabled
  - 2x public subnets (for ingress/NAT)
  - 2x private app subnets (for EKS nodes/services)
  - 2x private data subnets (for RDS)
  - Internet Gateway, route tables, and 2x NAT gateways (one per AZ)

  Why:
  - This matches the design’s “private-by-default” posture: only the edge is public.
  - Two AZs provides production-grade HA while avoiding the cost of three NAT gateways.

  Idempotency strategy:
  - Find resources by `tag:Name` and reuse them if they exist.
#>

Assert-CommandExists -Name "aws"

$tags = Get-DefaultTags -Prefix $Prefix -Environment $Environment
$azs = Get-AvailabilityZones2 -Region $Region
$az1 = $azs[0]
$az2 = $azs[1]

$vpcName = "$Prefix-vpc"
$vpc = Find-VpcByNameTag -Region $Region -Name $vpcName

if (-not $vpc) {
  Write-Host "Creating VPC $vpcName ($VpcCidr)"
  $tagSpec = ConvertTo-AwsTagSpec -ResourceType vpc -Tags ($tags + @(@{Key='Name';Value=$vpcName}))
  $vpc = Invoke-AwsJson -Command "ec2 create-vpc --cidr-block $VpcCidr --tag-specifications `"$tagSpec`"" -Region $Region
  $vpc = $vpc.Vpc

  # Enable DNS for private service discovery (EKS, private endpoints, etc.).
  Invoke-Expression "aws ec2 modify-vpc-attribute --region $Region --vpc-id $($vpc.VpcId) --enable-dns-support `{`\"Value`\":true`}" | Out-Null
  Invoke-Expression "aws ec2 modify-vpc-attribute --region $Region --vpc-id $($vpc.VpcId) --enable-dns-hostnames `{`\"Value`\":true`}" | Out-Null
} else {
  Write-Host "VPC exists: $($vpc.VpcId)"
}

$vpcId = $vpc.VpcId

function Ensure-Subnet {
  param(
    [string]$Name,
    [string]$Cidr,
    [string]$Az,
    [bool]$MapPublicIpOnLaunch
  )

  $existing = Find-SubnetByNameTag -Region $Region -VpcId $vpcId -Name $Name
  if ($existing) {
    Write-Host "Subnet exists: $Name ($($existing.SubnetId))"
    return $existing
  }

  Write-Host "Creating subnet $Name ($Cidr) in $Az"
  $tagSpec = ConvertTo-AwsTagSpec -ResourceType subnet -Tags ($tags + @(@{Key='Name';Value=$Name}))
  $created = Invoke-AwsJson -Command "ec2 create-subnet --vpc-id $vpcId --cidr-block $Cidr --availability-zone $Az --tag-specifications `"$tagSpec`"" -Region $Region
  $subnet = $created.Subnet

  # Public subnets need automatic public IP assignment for internet-facing resources like NAT.
  $value = if ($MapPublicIpOnLaunch) { "true" } else { "false" }
  Invoke-Expression "aws ec2 modify-subnet-attribute --region $Region --subnet-id $($subnet.SubnetId) --map-public-ip-on-launch `{`\"Value`\":$value`}" | Out-Null

  return $subnet
}

# CIDR plan (simple, deterministic): public (low), private app (mid), private data (high).
$subPublic1 = Ensure-Subnet -Name "$Prefix-public-$az1" -Cidr "10.20.0.0/20"   -Az $az1 -MapPublicIpOnLaunch $true
$subPublic2 = Ensure-Subnet -Name "$Prefix-public-$az2" -Cidr "10.20.16.0/20"  -Az $az2 -MapPublicIpOnLaunch $true
$subApp1    = Ensure-Subnet -Name "$Prefix-app-$az1"    -Cidr "10.20.128.0/20" -Az $az1 -MapPublicIpOnLaunch $false
$subApp2    = Ensure-Subnet -Name "$Prefix-app-$az2"    -Cidr "10.20.144.0/20" -Az $az2 -MapPublicIpOnLaunch $false
$subData1   = Ensure-Subnet -Name "$Prefix-data-$az1"   -Cidr "10.20.192.0/20" -Az $az1 -MapPublicIpOnLaunch $false
$subData2   = Ensure-Subnet -Name "$Prefix-data-$az2"   -Cidr "10.20.208.0/20" -Az $az2 -MapPublicIpOnLaunch $false

# Internet Gateway
$igwName = "$Prefix-igw"
$igw = Invoke-AwsJson -Command "ec2 describe-internet-gateways --filters Name=tag:Name,Values=$igwName" -Region $Region
$igw = $igw.InternetGateways | Select-Object -First 1
if (-not $igw) {
  Write-Host "Creating Internet Gateway $igwName"
  $tagSpec = ConvertTo-AwsTagSpec -ResourceType internet-gateway -Tags ($tags + @(@{Key='Name';Value=$igwName}))
  $igw = (Invoke-AwsJson -Command "ec2 create-internet-gateway --tag-specifications `"$tagSpec`"" -Region $Region).InternetGateway
  Invoke-Expression "aws ec2 attach-internet-gateway --region $Region --vpc-id $vpcId --internet-gateway-id $($igw.InternetGatewayId)" | Out-Null
} else {
  Write-Host "Internet Gateway exists: $($igw.InternetGatewayId)"
}

function Ensure-RouteTable {
  param([string]$Name)
  $rt = Invoke-AwsJson -Command "ec2 describe-route-tables --filters Name=vpc-id,Values=$vpcId Name=tag:Name,Values=$Name" -Region $Region
  $rt = $rt.RouteTables | Select-Object -First 1
  if ($rt) { return $rt }
  Write-Host "Creating route table $Name"
  $tagSpec = ConvertTo-AwsTagSpec -ResourceType route-table -Tags ($tags + @(@{Key='Name';Value=$Name}))
  return (Invoke-AwsJson -Command "ec2 create-route-table --vpc-id $vpcId --tag-specifications `"$tagSpec`"" -Region $Region).RouteTable
}

function Ensure-Route {
  param([string]$RouteTableId,[string]$DestinationCidr,[string]$TargetArg)
  # Creating a route that already exists errors; so we check first.
  $rt = Invoke-AwsJson -Command "ec2 describe-route-tables --route-table-ids $RouteTableId" -Region $Region
  $exists = $rt.RouteTables[0].Routes | Where-Object { $_.DestinationCidrBlock -eq $DestinationCidr -and $_.State -ne 'blackhole' }
  if ($exists) {
    Write-Host "Route exists: $RouteTableId -> $DestinationCidr"
    return
  }
  Write-Host "Creating route: $RouteTableId -> $DestinationCidr ($TargetArg)"
  Invoke-Expression "aws ec2 create-route --region $Region --route-table-id $RouteTableId --destination-cidr-block $DestinationCidr $TargetArg" | Out-Null
}

function Ensure-RouteTableAssociation {
  param([string]$RouteTableId,[string]$SubnetId)
  $rt = Invoke-AwsJson -Command "ec2 describe-route-tables --route-table-ids $RouteTableId" -Region $Region
  $assoc = $rt.RouteTables[0].Associations | Where-Object { $_.SubnetId -eq $SubnetId }
  if ($assoc) {
    Write-Host "Association exists: $RouteTableId <-> $SubnetId"
    return
  }
  Write-Host "Associating $SubnetId to route table $RouteTableId"
  Invoke-Expression "aws ec2 associate-route-table --region $Region --route-table-id $RouteTableId --subnet-id $SubnetId | Out-Null" | Out-Null
}

# Public route table (shared for both public subnets)
$rtPublic = Ensure-RouteTable -Name "$Prefix-rt-public"
Ensure-Route -RouteTableId $rtPublic.RouteTableId -DestinationCidr "0.0.0.0/0" -TargetArg "--gateway-id $($igw.InternetGatewayId)"
Ensure-RouteTableAssociation -RouteTableId $rtPublic.RouteTableId -SubnetId $subPublic1.SubnetId
Ensure-RouteTableAssociation -RouteTableId $rtPublic.RouteTableId -SubnetId $subPublic2.SubnetId

# NAT gateways (one per AZ) for private subnet egress.
function Ensure-EipForNat {
  param([string]$Name)
  $existing = Invoke-AwsJson -Command "ec2 describe-addresses --filters Name=tag:Name,Values=$Name" -Region $Region
  $existing = $existing.Addresses | Select-Object -First 1
  if ($existing) {
    Write-Host "EIP exists: $Name ($($existing.AllocationId))"
    return $existing
  }
  Write-Host "Allocating EIP for NAT: $Name"
  $eip = Invoke-AwsJson -Command "ec2 allocate-address --domain vpc" -Region $Region
  Ensure-Tagged -Region $Region -ResourceId $eip.AllocationId -Tags ($tags + @(@{Key='Name';Value=$Name}))
  return (Invoke-AwsJson -Command "ec2 describe-addresses --allocation-ids $($eip.AllocationId)" -Region $Region).Addresses[0]
}

function Ensure-NatGateway {
  param([string]$Name,[string]$PublicSubnetId,[string]$AllocationId)
  $existing = Invoke-AwsJson -Command "ec2 describe-nat-gateways --filter Name=vpc-id,Values=$vpcId Name=tag:Name,Values=$Name" -Region $Region
  $existing = $existing.NatGateways | Where-Object { $_.State -ne 'deleted' } | Select-Object -First 1
  if ($existing) {
    Write-Host "NAT Gateway exists: $Name ($($existing.NatGatewayId)) state=$($existing.State)"
    return $existing
  }
  Write-Host "Creating NAT Gateway $Name in subnet $PublicSubnetId"
  $tagSpec = ConvertTo-AwsTagSpec -ResourceType natgateway -Tags ($tags + @(@{Key='Name';Value=$Name}))
  $ngw = Invoke-AwsJson -Command "ec2 create-nat-gateway --subnet-id $PublicSubnetId --allocation-id $AllocationId --tag-specifications `"$tagSpec`"" -Region $Region
  return $ngw.NatGateway
}

$eip1 = Ensure-EipForNat -Name "$Prefix-eip-nat-$az1"
$eip2 = Ensure-EipForNat -Name "$Prefix-eip-nat-$az2"
$nat1 = Ensure-NatGateway -Name "$Prefix-nat-$az1" -PublicSubnetId $subPublic1.SubnetId -AllocationId $eip1.AllocationId
$nat2 = Ensure-NatGateway -Name "$Prefix-nat-$az2" -PublicSubnetId $subPublic2.SubnetId -AllocationId $eip2.AllocationId

Write-Host "Waiting for NAT gateways to become available (this can take several minutes)..."
Invoke-Expression "aws ec2 wait nat-gateway-available --region $Region --nat-gateway-ids $($nat1.NatGatewayId) $($nat2.NatGatewayId)" | Out-Null

# Private route tables (one per AZ) to keep egress AZ-local.
$rtPriv1 = Ensure-RouteTable -Name "$Prefix-rt-private-$az1"
$rtPriv2 = Ensure-RouteTable -Name "$Prefix-rt-private-$az2"
Ensure-Route -RouteTableId $rtPriv1.RouteTableId -DestinationCidr "0.0.0.0/0" -TargetArg "--nat-gateway-id $($nat1.NatGatewayId)"
Ensure-Route -RouteTableId $rtPriv2.RouteTableId -DestinationCidr "0.0.0.0/0" -TargetArg "--nat-gateway-id $($nat2.NatGatewayId)"

# Associate private subnets with the AZ-local route table.
Ensure-RouteTableAssociation -RouteTableId $rtPriv1.RouteTableId -SubnetId $subApp1.SubnetId
Ensure-RouteTableAssociation -RouteTableId $rtPriv2.RouteTableId -SubnetId $subApp2.SubnetId
Ensure-RouteTableAssociation -RouteTableId $rtPriv1.RouteTableId -SubnetId $subData1.SubnetId
Ensure-RouteTableAssociation -RouteTableId $rtPriv2.RouteTableId -SubnetId $subData2.SubnetId

Write-Host "Network foundation complete."
Write-Host "Next: 04-Validate-Network.ps1"

