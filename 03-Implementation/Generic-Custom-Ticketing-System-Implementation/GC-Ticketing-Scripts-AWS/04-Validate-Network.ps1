param(
  [string]$Prefix = "gc-tkt-prod",
  [string]$Environment = "prod",
  [string]$Region = "us-east-1"
)

. "$PSScriptRoot\\_common.ps1"

<#
  04-Validate-Network.ps1

  Validates the network created by 03-Create-Network.ps1.
  This script is safe to re-run and prints resource IDs you’ll need for troubleshooting.

  Manual verification (AWS Console):
  - VPC -> Your VPCs: confirm VPC exists and DNS is enabled
  - VPC -> Subnets: confirm 2 public, 2 app-private, 2 data-private subnets
  - VPC -> NAT Gateways: confirm NATs are “Available”
  - VPC -> Route Tables: confirm private routes point to NATs and public routes point to IGW
#>

Assert-CommandExists -Name "aws"

$vpcName = "$Prefix-vpc"
$vpc = Find-VpcByNameTag -Region $Region -Name $vpcName
if (-not $vpc) { throw "Missing VPC with Name tag '$vpcName'. Run 03-Create-Network.ps1." }

Write-Host "VPC: $($vpc.VpcId) CIDR=$($vpc.CidrBlock)"

$subnets = Invoke-AwsJson -Command "ec2 describe-subnets --filters Name=vpc-id,Values=$($vpc.VpcId)" -Region $Region
$subnets.Subnets | Select-Object SubnetId,AvailabilityZone,CidrBlock,@{n='Name';e={($_.Tags|? Key -eq 'Name').Value}} | Format-Table

$igws = Invoke-AwsJson -Command "ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values=$($vpc.VpcId)" -Region $Region
Write-Host "IGW attached: $($igws.InternetGateways[0].InternetGatewayId)"

$nats = Invoke-AwsJson -Command "ec2 describe-nat-gateways --filter Name=vpc-id,Values=$($vpc.VpcId) Name=state,Values=available" -Region $Region
Write-Host ("NAT gateways available: " + ($nats.NatGateways | Select-Object -ExpandProperty NatGatewayId) -join ", ")

$rts = Invoke-AwsJson -Command "ec2 describe-route-tables --filters Name=vpc-id,Values=$($vpc.VpcId)" -Region $Region
Write-Host "Route tables:"
$rts.RouteTables | Select-Object RouteTableId,@{n='Name';e={($_.Tags|? Key -eq 'Name').Value}} | Format-Table

