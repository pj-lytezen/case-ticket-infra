param(
  [string]$Prefix = "gc-tkt-prod",
  [string]$Location = "eastus",
  [string]$KeyVaultName = ""
)

. "$PSScriptRoot\\_common.ps1"

<#
  05-Create-Security.ps1 (Azure)

  Creates:
  - Key Vault for secrets (DB passwords, app config)
  - Log Analytics workspace (for AKS monitoring + centralized logs)

  Why:
  - Separates secrets from code and from the cluster.
  - Centralizes telemetry so you can measure retrieval/evaluator/escalation behavior (a core design requirement).

  Idempotency:
  - Uses deterministic names based on Prefix + Subscription suffix; if resources exist, reuses them.

  Important:
  - Key Vault names are globally unique. If your desired name is taken, pass -KeyVaultName explicitly.
#>

Assert-CommandExists -Name "az"

$rg = Get-ResourceGroupName -Prefix $Prefix
Ensure-ResourceGroup -Name $rg -Location $Location

$suffix = Get-DeterministicSuffix
$defaultKv = To-GlobalName -Base ("kv$Prefix$suffix") -MaxLen 24
$keyVaultName = if ($KeyVaultName) { $KeyVaultName } else { $defaultKv }
$lawName = "law-$Prefix"

function Ensure-LogAnalytics {
  try {
    $law = Invoke-AzJson "monitor log-analytics workspace show -g $rg -n $lawName"
    Write-Host "Log Analytics workspace exists: $lawName"
    return $law
  } catch { }

  Write-Host "Creating Log Analytics workspace: $lawName"
  return Invoke-AzJson "monitor log-analytics workspace create -g $rg -n $lawName -l $Location --tags Project=SupportTicketAutomation Prefix=$Prefix"
}

function Ensure-KeyVault {
  try {
    $kv = Invoke-AzJson "keyvault show -g $rg -n $keyVaultName"
    Write-Host "Key Vault exists: $keyVaultName"
    return $kv
  } catch { }

  Write-Host "Creating Key Vault: $keyVaultName"

  # We enable RBAC authorization (modern default). If your org requires access policies instead:
  # - Create with --enable-rbac-authorization false
  # - Then set access policies with az keyvault set-policy
  $kv = Invoke-AzJson "keyvault create -g $rg -n $keyVaultName -l $Location --enable-rbac-authorization true --sku standard --tags Project=SupportTicketAutomation Prefix=$Prefix"

  # Grant the current principal permission to manage secrets (required to set/retrieve secrets in later scripts).
  # If this fails due to directory permissions, do it manually in the portal:
  #   Key Vault -> Access control (IAM) -> Add role assignment -> Key Vault Secrets Officer
  try {
    $principalId = (Invoke-Expression "az ad signed-in-user show --query id -o tsv").Trim()
    $scope = $kv.id
    Invoke-Expression "az role assignment create --assignee-object-id $principalId --assignee-principal-type User --role \"Key Vault Secrets Officer\" --scope $scope | Out-Null" | Out-Null
    Write-Host "Assigned Key Vault Secrets Officer to current user."
  } catch {
    Write-Host "WARNING: Could not auto-assign Key Vault role. You may need to assign it manually."
  }

  return $kv
}

function New-RandomPassword {
  param([int]$Length = 28)
  $chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789"
  -join (1..$Length | ForEach-Object { $chars[(Get-Random -Minimum 0 -Maximum $chars.Length)] })
}

function Ensure-Secret {
  param([string]$SecretName,[string]$SecretValue)
  try {
    Invoke-Expression "az keyvault secret show --vault-name $keyVaultName -n $SecretName | Out-Null" | Out-Null
    Write-Host "Secret exists: $SecretName"
    return
  } catch { }

  Write-Host "Creating secret: $SecretName"
  Invoke-Expression "az keyvault secret set --vault-name $keyVaultName -n $SecretName --value `"$SecretValue`" | Out-Null" | Out-Null
}

$law = Ensure-LogAnalytics
$kv = Ensure-KeyVault

# Store DB credentials for Postgres Flexible Server.
Ensure-Secret -SecretName "pg-admin-user" -SecretValue "pgadmin"
Ensure-Secret -SecretName "pg-admin-password" -SecretValue (New-RandomPassword)

# Placeholder app config secret.
Ensure-Secret -SecretName "app-config-json" -SecretValue (@{ environment="prod"; notes="fill after provisioning" } | ConvertTo-Json -Compress)

Write-Host "Security complete."
Write-Host "Key Vault: $keyVaultName"
Write-Host "Log Analytics: $lawName"
Write-Host "Next: 06-Validate-Security.ps1"
