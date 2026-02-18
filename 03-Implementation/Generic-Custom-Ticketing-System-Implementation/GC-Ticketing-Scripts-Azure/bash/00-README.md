# Azure Bash Implementation Scripts (Generic Custom Ticketing System)

This folder contains **bash** equivalents of the PowerShell scripts in the parent directory.

## Prerequisites
- Bash 4+ (Linux/macOS; on Windows use WSL or Git Bash)
- `az` (Azure CLI)

## Authentication / Subscription selection
- `az login`
- `az account set --subscription <SUBSCRIPTION_ID>`

## How to run
Run scripts in numeric order. Each create script has a matching validation script.

Example:
- `./01-Context.sh --prefix gc-tkt-prod --location eastus`
- `./03-Create-Network.sh --prefix gc-tkt-prod --location eastus`
- `./11-Create-AKS.sh --prefix gc-tkt-prod --location eastus`

## Conventions
- Resource group: `rg-<prefix>`
- VNet: `vnet-<prefix>`
- AKS: `aks-<prefix>`
- Many global-unique names (Key Vault, Storage, ACR, Postgres server DNS) derive from:
  - `<prefix>` plus a stable suffix based on subscription id
  - You can override those names via optional flags where provided.

