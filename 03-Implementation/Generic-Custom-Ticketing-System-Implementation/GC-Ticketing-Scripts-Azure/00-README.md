# Azure CLI Implementation Scripts (Generic Custom Ticketing System)

These scripts provision the **Azure** infrastructure for the Generic Custom Ticketing System design.

## Prerequisites
- Install **Azure CLI** (`az`) and ensure it’s on your `PATH`.
- Authenticate: `az login`
- Select subscription: `az account set --subscription <SUBSCRIPTION_ID>`
- Permissions: ability to create Resource Groups, VNets, NAT Gateway, AKS, PostgreSQL Flexible Server, Storage, Service Bus, Key Vault, Private DNS, and Private Endpoints.

## How to run
Run in numeric order (01-, 02-, 03-, …). Each creation script is followed by a validation script.

Example:
- `.\01-Context.ps1 -Prefix gc-tkt-prod -Location eastus`
- `.\03-Create-Network.ps1 -Prefix gc-tkt-prod -Location eastus`
- `.\11-Create-AKS.ps1 -Prefix gc-tkt-prod -Location eastus`

## Conventions
- A resource group named `rg-<Prefix>` is created (or reused).
- Resources are named deterministically from `-Prefix` to keep scripts idempotent.
- These scripts create infrastructure only; application deployment to AKS is a later step.

