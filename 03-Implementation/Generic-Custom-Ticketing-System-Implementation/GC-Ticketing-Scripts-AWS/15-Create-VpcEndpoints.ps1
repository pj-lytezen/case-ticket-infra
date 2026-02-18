param(
  [string]$Prefix = "gc-tkt-prod",
  [string]$Environment = "prod",
  [string]$Region = "us-east-1"
)

. "$PSScriptRoot\\_common.ps1"

<#
  15-Create-VpcEndpoints.ps1

  Creates VPC endpoints to reduce NAT Gateway data processing charges and improve security:
  - Gateway endpoint: S3 (so S3 traffic stays on AWS network, not via NAT)
  - Interface endpoints: SQS, Secrets Manager, CloudWatch Logs, ECR (api+dkr), STS

  Why:
  - In private subnet architectures, NAT Gateway per-GB processing can become a major cost driver.
  - Private endpoints keep traffic off the public internet and reduce the attack surface.

  Idempotency:
  - Endpoints are discovered by (VPC, service-name) and only created if missing.
#>

Assert-CommandExists -Name "aws"

$tags = Get-DefaultTags -Prefix $Prefix -Environment $Environment
$azs = Get-AvailabilityZones2 -Region $Region

$vpc = Find-VpcByNameTag -Region $Region -Name "$Prefix-vpc"
if (-not $vpc) { throw "Missing VPC. Run 03-Create-Network.ps1." }
$vpcId = $vpc.VpcId

$subApp1 = Find-SubnetByNameTag -Region $Region -VpcId $vpcId -Name "$Prefix-app-$($azs[0])"
$subApp2 = Find-SubnetByNameTag -Region $Region -VpcId $vpcId -Name "$Prefix-app-$($azs[1])"
if (-not $subApp1 -or -not $subApp2) { throw "Missing app subnets." }

function Find-RouteTableByName {
  param([string]$Name)
  $rt = Invoke-AwsJson -Command "ec2 describe-route-tables --filters Name=vpc-id,Values=$vpcId Name=tag:Name,Values=$Name" -Region $Region
  $rt.RouteTables | Select-Object -First 1
}

$rt1 = Find-RouteTableByName -Name "$Prefix-rt-private-$($azs[0])"
$rt2 = Find-RouteTableByName -Name "$Prefix-rt-private-$($azs[1])"
if (-not $rt1 -or -not $rt2) { throw "Missing private route tables. Run 03-Create-Network.ps1." }

function Ensure-GatewayEndpointS3 {
  $svc = "com.amazonaws.$Region.s3"
  $existing = Invoke-AwsJson -Command "ec2 describe-vpc-endpoints --filters Name=vpc-id,Values=$vpcId Name=service-name,Values=$svc" -Region $Region
  $existing = $existing.VpcEndpoints | Where-Object { $_.State -ne 'deleted' } | Select-Object -First 1
  if ($existing) {
    Write-Host "S3 gateway endpoint exists: $($existing.VpcEndpointId)"
    return
  }
  Write-Host "Creating S3 gateway endpoint"
  $tagSpec = ConvertTo-AwsTagSpec -ResourceType vpc-endpoint -Tags ($tags + @(@{Key='Name';Value="$Prefix-vpce-s3"}))
  Invoke-Expression "aws ec2 create-vpc-endpoint --region $Region --vpc-id $vpcId --vpc-endpoint-type Gateway --service-name $svc --route-table-ids $($rt1.RouteTableId) $($rt2.RouteTableId) --tag-specifications `"$tagSpec`" | Out-Null" | Out-Null
}

function Ensure-InterfaceEndpoint {
  param([string]$ServiceShort,[string]$NameTag)
  $svc = "com.amazonaws.$Region.$ServiceShort"
  $existing = Invoke-AwsJson -Command "ec2 describe-vpc-endpoints --filters Name=vpc-id,Values=$vpcId Name=service-name,Values=$svc" -Region $Region
  $existing = $existing.VpcEndpoints | Where-Object { $_.State -ne 'deleted' } | Select-Object -First 1
  if ($existing) {
    Write-Host "Interface endpoint exists for $ServiceShort: $($existing.VpcEndpointId)"
    return
  }

  # SG for interface endpoints (HTTPS from within VPC).
  $sgName = "$Prefix-vpce-sg"
  $sg = Find-SgByName -Region $Region -VpcId $vpcId -GroupName $sgName
  if (-not $sg) {
    Write-Host "Creating VPC endpoint SG: $sgName"
    $sgId = (Invoke-AwsJson -Command "ec2 create-security-group --vpc-id $vpcId --group-name $sgName --description `"$Prefix VPC endpoints SG`"" -Region $Region).GroupId
    Ensure-Tagged -Region $Region -ResourceId $sgId -Tags ($tags + @(@{Key='Name';Value=$sgName}))
    Invoke-Expression "aws ec2 authorize-security-group-ingress --region $Region --group-id $sgId --ip-permissions IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges=[{CidrIp=$($vpc.CidrBlock),Description=`"VPC internal`"}] 2>$null" | Out-Null
    $sg = (Invoke-AwsJson -Command "ec2 describe-security-groups --group-ids $sgId" -Region $Region).SecurityGroups[0]
  }

  Write-Host "Creating interface endpoint for $ServiceShort"
  $tagSpec = ConvertTo-AwsTagSpec -ResourceType vpc-endpoint -Tags ($tags + @(@{Key='Name';Value=$NameTag}))
  Invoke-Expression @"
aws ec2 create-vpc-endpoint --region $Region `
  --vpc-id $vpcId `
  --vpc-endpoint-type Interface `
  --service-name $svc `
  --subnet-ids $($subApp1.SubnetId) $($subApp2.SubnetId) `
  --security-group-ids $($sg.GroupId) `
  --private-dns-enabled `
  --tag-specifications "$tagSpec" | Out-Null
"@ | Out-Null
}

Ensure-GatewayEndpointS3
Ensure-InterfaceEndpoint -ServiceShort "sqs"            -NameTag "$Prefix-vpce-sqs"
Ensure-InterfaceEndpoint -ServiceShort "secretsmanager" -NameTag "$Prefix-vpce-secrets"
Ensure-InterfaceEndpoint -ServiceShort "logs"           -NameTag "$Prefix-vpce-logs"
Ensure-InterfaceEndpoint -ServiceShort "ecr.api"        -NameTag "$Prefix-vpce-ecr-api"
Ensure-InterfaceEndpoint -ServiceShort "ecr.dkr"        -NameTag "$Prefix-vpce-ecr-dkr"
Ensure-InterfaceEndpoint -ServiceShort "sts"            -NameTag "$Prefix-vpce-sts"

Write-Host "VPC endpoints provisioning requested."
Write-Host "Next: 16-Validate-VpcEndpoints.ps1"

