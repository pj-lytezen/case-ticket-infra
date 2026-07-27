# Azure Cost Runbooks (az-implementation-v1)

This folder contains start/stop runbooks and a Postgres backup helper for the
Generic Custom Ticketing System Azure deployment. The scripts are parameterized
via `parameters.ps1` and target the shared resource group.

## Runbooks

- `stop-dev.ps1` (delete preference)
  - Deletes cost-heavy resources when idle:
    - AKS, ACR, Service Bus, Postgres, NAT + Public IP, private endpoints,
      Log Analytics.
  - Storage account and Key Vault are left intact to preserve data and secrets.

- `start-dev.ps1`
  - Recreates the environment using the standard provisioning scripts.
  - Validations run by default.

- `backup-postgres-to-blob.ps1`
  - Exports `gc_ticketing` using `pg_dump` and uploads it to Blob storage.

## Usage

```powershell
# Delete-cost runbook
.\az-implementation-v1\stop-dev.ps1

# Recreate environment
.\az-implementation-v1\start-dev.ps1

# Backup Postgres to Blob (requires pg_dump + network access)
.\az-implementation-v1\backup-postgres-to-blob.ps1
```

## Notes

- The backup script requires `pg_dump` on PATH and network access to the
  private Postgres endpoint (run from a VNet-connected host).
- `stop-dev.ps1` uses delete by default to minimize costs; resources are
  re-created by `start-dev.ps1` as needed.
- You can change defaults (or add switches) in `stop-dev.ps1` if you want to
  keep specific services running.
