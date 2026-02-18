param(
  [string]$Prefix = "gc-tkt-prod",
  [string]$Environment = "prod",
  [string]$Region = "us-east-1",
  [string]$DbInstanceClass = "db.t4g.medium",
  [int]$AllocatedStorageGb = 200
)

. "$PSScriptRoot\\_common.ps1"

<#
  13-Create-Database.ps1

  Creates an RDS PostgreSQL instance for:
  - sessions/messages/events
  - tickets/comments
  - Hybrid RAG indexes (FTS + pgvector)
  - outbox table

  Why RDS Postgres:
  - Lowest operational burden for production.
  - Supports full-text search and pgvector in many configurations.

  Idempotency:
  - DB subnet group is checked by name.
  - Security group is checked by group-name.
  - RDS instance is checked by DBInstanceIdentifier.

  Security note:
  - For a first production iteration, we allow DB access from inside the VPC CIDR.
  - After EKS is stable, tighten DB SG ingress to nodegroup security group(s) only.
#>

Assert-CommandExists -Name "aws"

$tags = Get-DefaultTags -Prefix $Prefix -Environment $Environment
$azs = Get-AvailabilityZones2 -Region $Region

$vpcName = "$Prefix-vpc"
$vpc = Find-VpcByNameTag -Region $Region -Name $vpcName
if (-not $vpc) { throw "Missing VPC. Run 03-Create-Network.ps1." }
$vpcId = $vpc.VpcId

$subData1 = Find-SubnetByNameTag -Region $Region -VpcId $vpcId -Name "$Prefix-data-$($azs[0])"
$subData2 = Find-SubnetByNameTag -Region $Region -VpcId $vpcId -Name "$Prefix-data-$($azs[1])"
if (-not $subData1 -or -not $subData2) { throw "Missing data subnets. Run 03-Create-Network.ps1." }

# DB subnet group (RDS requires subnets in 2+ AZs for Multi-AZ).
$subnetGroupName = "$Prefix-db-subnets"
try {
  $sg = Invoke-AwsJson -Command "rds describe-db-subnet-groups --db-subnet-group-name $subnetGroupName" -Region $Region
  Write-Host "DB subnet group exists: $subnetGroupName"
} catch {
  Write-Host "Creating DB subnet group: $subnetGroupName"
  Invoke-Expression "aws rds create-db-subnet-group --region $Region --db-subnet-group-name $subnetGroupName --db-subnet-group-description `"$Prefix DB subnet group`" --subnet-ids $($subData1.SubnetId) $($subData2.SubnetId) | Out-Null" | Out-Null
}

# DB security group
$dbSgName = "$Prefix-db-sg"
$dbSg = Find-SgByName -Region $Region -VpcId $vpcId -GroupName $dbSgName
if (-not $dbSg) {
  Write-Host "Creating DB security group: $dbSgName"
  $dbSgId = (Invoke-AwsJson -Command "ec2 create-security-group --vpc-id $vpcId --group-name $dbSgName --description `"$Prefix RDS Postgres SG`"" -Region $Region).GroupId
  Ensure-Tagged -Region $Region -ResourceId $dbSgId -Tags ($tags + @(@{Key='Name';Value=$dbSgName}))

  # Allow Postgres from within VPC. Tighten later to EKS node SGs.
  Invoke-Expression "aws ec2 authorize-security-group-ingress --region $Region --group-id $dbSgId --ip-permissions IpProtocol=tcp,FromPort=5432,ToPort=5432,IpRanges=[{CidrIp=$($vpc.CidrBlock),Description=`"VPC internal`"}] 2>$null" | Out-Null

  $dbSg = (Invoke-AwsJson -Command "ec2 describe-security-groups --group-ids $dbSgId" -Region $Region).SecurityGroups[0]
}

# Retrieve master credentials from Secrets Manager.
$secretName = "$Prefix/rds/master"
$secret = Invoke-AwsJson -Command "secretsmanager get-secret-value --secret-id `"$secretName`"" -Region $Region
$cred = $secret.SecretString | ConvertFrom-Json

$dbId = "$Prefix-pg"
$dbExists = $false
try {
  $db = Invoke-AwsJson -Command "rds describe-db-instances --db-instance-identifier $dbId" -Region $Region
  $dbExists = $true
  Write-Host "RDS instance exists: $dbId status=$($db.DBInstances[0].DBInstanceStatus)"
} catch { }

if (-not $dbExists) {
  Write-Host "Creating RDS PostgreSQL instance: $dbId (Multi-AZ)"

  # Minimal production hardening:
  # - encryption at rest (default KMS for RDS unless you specify a custom key)
  # - deletion protection (prevents accidental deletion)
  # - backup retention
  Invoke-Expression @"
aws rds create-db-instance --region $Region `
  --db-instance-identifier $dbId `
  --engine postgres `
  --db-instance-class $DbInstanceClass `
  --allocated-storage $AllocatedStorageGb `
  --multi-az `
  --storage-type gp3 `
  --db-subnet-group-name $subnetGroupName `
  --vpc-security-group-ids $($dbSg.GroupId) `
  --master-username $($cred.username) `
  --master-user-password $($cred.password) `
  --backup-retention-period 7 `
  --no-publicly-accessible `
  --deletion-protection `
  --tags Key=Project,Value=SupportTicketAutomation Key=Environment,Value=$Environment Key=Prefix,Value=$Prefix Key=Name,Value=$dbId | Out-Null
"@ | Out-Null
}

Write-Host "Waiting for DB to become AVAILABLE (this can take 15–45 minutes)..."
Invoke-Expression "aws rds wait db-instance-available --region $Region --db-instance-identifier $dbId" | Out-Null

$db = Invoke-AwsJson -Command "rds describe-db-instances --db-instance-identifier $dbId" -Region $Region
$endpoint = $db.DBInstances[0].Endpoint.Address
$port = $db.DBInstances[0].Endpoint.Port
Write-Host "RDS available: $endpoint:$port"
Write-Host "Next: 14-Validate-Database.ps1"

