Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
  Common helpers for AWS provisioning scripts.

  Why a shared file:
  - Keeps scripts consistent and idempotent.
  - Centralizes “how we find existing resources” (by tags/Name).
  - Avoids copy/paste drift across scripts.

  Import pattern:
    . "$PSScriptRoot\\_common.ps1"
#>

function Assert-CommandExists {
  param([Parameter(Mandatory=$true)][string]$Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required command '$Name' was not found on PATH. Install it and retry."
  }
}

function Invoke-AwsJson {
  <#
    Runs an AWS CLI command and parses JSON output.
    Use this wrapper so scripts can reliably extract IDs and avoid brittle string parsing.
  #>
  param(
    [Parameter(Mandatory=$true)][string]$Command,
    [Parameter(Mandatory=$true)][string]$Region
  )
  $full = "aws $Command --region $Region --output json"
  $raw = Invoke-Expression $full
  if (-not $raw) { return $null }
  return $raw | ConvertFrom-Json
}

function Get-AwsAccountId {
  param([Parameter(Mandatory=$true)][string]$Region)
  (Invoke-AwsJson -Command "sts get-caller-identity" -Region $Region).Account
}

function Get-DefaultTags {
  param(
    [Parameter(Mandatory=$true)][string]$Prefix,
    [Parameter(Mandatory=$true)][string]$Environment
  )

  # Tagging is the backbone of idempotency for AWS resources that don’t have unique names.
  # We standardize on Name + a few “cost allocation / ownership” tags.
  @(
    @{ Key = 'Project'; Value = 'SupportTicketAutomation' },
    @{ Key = 'Environment'; Value = $Environment },
    @{ Key = 'Owner'; Value = $env:USERNAME },
    @{ Key = 'Prefix'; Value = $Prefix }
  )
}

function ConvertTo-AwsTagSpec {
  <#
    Converts a tag array to the "ResourceType=...,Tags=[{Key=,Value=}]" string used by many AWS create APIs.
  #>
  param(
    [Parameter(Mandatory=$true)][string]$ResourceType,
    [Parameter(Mandatory=$true)][array]$Tags
  )

  $tagsInline = ($Tags | ForEach-Object { "{Key=$($_.Key),Value=$($_.Value)}" }) -join ','
  "ResourceType=$ResourceType,Tags=[$tagsInline]"
}

function Ensure-Tagged {
  <#
    Applies tags to a resource if it exists. Safe to run repeatedly.
  #>
  param(
    [Parameter(Mandatory=$true)][string]$Region,
    [Parameter(Mandatory=$true)][string]$ResourceId,
    [Parameter(Mandatory=$true)][array]$Tags
  )
  $tagsInline = ($Tags | ForEach-Object { "Key=$($_.Key),Value=$($_.Value)" }) -join ' '
  Invoke-Expression "aws ec2 create-tags --region $Region --resources $ResourceId --tags $tagsInline | Out-Null"
}

function Get-AvailabilityZones2 {
  <#
    Returns two AZ names for the chosen region.
    We use two AZs to balance HA (production) with cost (NAT gateways and subnets scale per AZ).
  #>
  param([Parameter(Mandatory=$true)][string]$Region)
  $azs = Invoke-AwsJson -Command "ec2 describe-availability-zones --filters Name=region-name,Values=$Region Name=state,Values=available" -Region $Region
  $names = $azs.AvailabilityZones | Select-Object -ExpandProperty ZoneName
  if ($names.Count -lt 2) { throw "Region $Region has fewer than 2 available AZs." }
  return @($names[0], $names[1])
}

function Find-VpcByNameTag {
  param([Parameter(Mandatory=$true)][string]$Region,[Parameter(Mandatory=$true)][string]$Name)
  $res = Invoke-AwsJson -Command "ec2 describe-vpcs --filters Name=tag:Name,Values=$Name" -Region $Region
  return $res.Vpcs | Select-Object -First 1
}

function Find-SubnetByNameTag {
  param([Parameter(Mandatory=$true)][string]$Region,[Parameter(Mandatory=$true)][string]$VpcId,[Parameter(Mandatory=$true)][string]$Name)
  $res = Invoke-AwsJson -Command "ec2 describe-subnets --filters Name=vpc-id,Values=$VpcId Name=tag:Name,Values=$Name" -Region $Region
  return $res.Subnets | Select-Object -First 1
}

function Find-SgByName {
  param([Parameter(Mandatory=$true)][string]$Region,[Parameter(Mandatory=$true)][string]$VpcId,[Parameter(Mandatory=$true)][string]$GroupName)
  $res = Invoke-AwsJson -Command "ec2 describe-security-groups --filters Name=vpc-id,Values=$VpcId Name=group-name,Values=$GroupName" -Region $Region
  return $res.SecurityGroups | Select-Object -First 1
}

