param(
  [string]$Prefix = "gc-tkt-prod",
  [string]$Location = "eastus"
)

. "$PSScriptRoot\\_common.ps1"

<#
  01-Context.ps1 (Azure)

  Purpose:
  - Pre-flight checks: confirm Azure CLI is installed and authenticated.
  - Print subscription and tenant context so you don’t accidentally deploy to the wrong place.

  Idempotency:
  - No cloud resources are created here; it validates local/auth context.
#>

Assert-CommandExists -Name "az"

Write-Host "Prefix=$Prefix Location=$Location"

$acct = Invoke-AzJson "account show"
Write-Host "Subscription: $($acct.name) ($($acct.id))"
Write-Host "Tenant      : $($acct.tenantId)"
Write-Host "User/Service: $($acct.user.name) ($($acct.user.type))"

Write-Host "Context OK. Next: 03-Create-Network.ps1"

