# AWS Bash Implementation Scripts (Generic Custom Ticketing System)

This folder contains **bash** equivalents of the PowerShell scripts in the parent directory.

## Prerequisites
- Bash 4+ (Linux/macOS; on Windows use WSL or Git Bash)
- `aws` (AWS CLI v2)
- `jq` (used for safe JSON parsing in idempotency checks)

## Authentication
- `aws configure` (access keys) **or**
- `aws sso login` (SSO)

## How to run
Run scripts in numeric order. Each create script has a matching validation script.

Example:
- `./01-Context.sh --prefix gc-tkt-prod --region us-east-1`
- `./03-Create-Network.sh --prefix gc-tkt-prod --region us-east-1`
- `./04-Validate-Network.sh --prefix gc-tkt-prod --region us-east-1`

## Notes
- Scripts are **idempotent**: they check for existing resources by `Name` tag and reuse them.
- Some steps (EKS/RDS/NAT) can take a long time in production.
- These scripts create infrastructure only; they do not deploy Kubernetes manifests or application containers.

