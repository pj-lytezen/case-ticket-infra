Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
  Common helpers for Google Cloud provisioning scripts (gcloud based).

  Import pattern:
    . "$PSScriptRoot\\_common.ps1"

  Why:
  - Standardizes JSON parsing
  - Simplifies idempotent “get-or-create” checks
#>

function Assert-CommandExists {
  param([Parameter(Mandatory=$true)][string]$Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required command '$Name' was not found on PATH. Install it and retry."
  }
}

function Invoke-GcloudJson {
  param([Parameter(Mandatory=$true)][string]$Command)
  $raw = Invoke-Expression "gcloud $Command --format=json"
  if (-not $raw) { return $null }
  return $raw | ConvertFrom-Json
}

function To-GcName {
  param([string]$Base,[int]$MaxLen = 63)
  $clean = ($Base.ToLower() -replace '[^a-z0-9-]', '-')
  $clean = ($clean -replace '-+', '-').Trim('-')
  if ($clean.Length -gt $MaxLen) { return $clean.Substring(0, $MaxLen).Trim('-') }
  return $clean
}

