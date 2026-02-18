param(
  [string]$Prefix = "gc-tkt-prod",
  [string]$Region = "us-east-1"
)

. "$PSScriptRoot\\_common.ps1"

<#
  16-Validate-VpcEndpoints.ps1

  Validates VPC endpoints created by 15-Create-VpcEndpoints.ps1.

  Manual verification (AWS Console):
  - VPC -> Endpoints: confirm endpoints are “Available”
  - VPC -> Endpoints: confirm Private DNS is enabled for interface endpoints
#>

Assert-CommandExists -Name "aws"

$vpc = Find-VpcByNameTag -Region $Region -Name "$Prefix-vpc"
if (-not $vpc) { throw "Missing VPC." }
$vpcId = $vpc.VpcId

$eps = Invoke-AwsJson -Command "ec2 describe-vpc-endpoints --filters Name=vpc-id,Values=$vpcId" -Region $Region
$eps.VpcEndpoints | Select-Object VpcEndpointId,ServiceName,VpcEndpointType,State,PrivateDnsEnabled | Format-Table

