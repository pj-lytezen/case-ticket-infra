param(
  [string]$Prefix = "gc-tkt-prod",
  [string]$Region = "us-east-1"
)

. "$PSScriptRoot\\_common.ps1"

<#
  14-Validate-Database.ps1

  Validates the RDS instance created by 13-Create-Database.ps1.

  Manual verification (AWS Console):
  - RDS -> Databases: confirm $Prefix-pg is “Available”, Multi-AZ = Yes, Public access = No
  - VPC security groups: confirm inbound rule on port 5432 is limited to internal networks/SGs
#>

Assert-CommandExists -Name "aws"

$dbId = "$Prefix-pg"
$db = Invoke-AwsJson -Command "rds describe-db-instances --db-instance-identifier $dbId" -Region $Region
$i = $db.DBInstances[0]
Write-Host "DB: $dbId status=$($i.DBInstanceStatus) engine=$($i.Engine) class=$($i.DBInstanceClass) multiAZ=$($i.MultiAZ)"
Write-Host "Endpoint: $($i.Endpoint.Address):$($i.Endpoint.Port)"
Write-Host "SubnetGroup: $($i.DBSubnetGroup.DBSubnetGroupName)"
Write-Host "SGs: " ($i.VpcSecurityGroups | ForEach-Object { $_.VpcSecurityGroupId } | Sort-Object | Out-String)

