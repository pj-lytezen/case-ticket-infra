# AWS CLI Implementation Scripts (Generic Custom Ticketing System)

These scripts provision the **AWS** infrastructure for the Generic Custom Ticketing System design.

## Prerequisites
- Install **AWS CLI v2** and ensure `aws` is on your `PATH`.
- Authenticate: `aws configure` (or SSO via `aws sso login`).
- Permissions: ability to create VPC, IAM roles/policies, EKS, RDS, S3, SQS, KMS, and VPC endpoints.

## How to run
Run scripts in numeric order (01-, 02-, 03-, …). Each creation script is followed by a validation script.

Example:
- `.\01-Context.ps1 -Prefix gc-tkt-prod -Region us-east-1`
- `.\02-Validate-Context.ps1 -Prefix gc-tkt-prod -Region us-east-1`
- `.\03-Create-Network.ps1 -Prefix gc-tkt-prod -Region us-east-1`
- `.\04-Validate-Network.ps1 -Prefix gc-tkt-prod -Region us-east-1`

## Conventions
- All resources are named with the provided `-Prefix`.
- Scripts are **idempotent**: they look up resources by name/tag and only create what’s missing.
- Tags are applied wherever supported to make lookup and cost allocation predictable.

## Notes
- EKS and RDS provisioning can take 10–45 minutes depending on region and capacity.
- These scripts provision infrastructure; they do **not** deploy Kubernetes manifests or application containers.

