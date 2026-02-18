# Google Cloud CLI Implementation Scripts (Generic Custom Ticketing System)

These scripts provision the **Google Cloud (GCP)** infrastructure for the Generic Custom Ticketing System design.

## Prerequisites
- Install **Google Cloud CLI** (`gcloud`) and ensure it’s on your `PATH`.
- Authenticate: `gcloud auth login` (and `gcloud auth application-default login` if needed for SDKs).
- Select project: `gcloud config set project <PROJECT_ID>`
- Permissions: ability to create VPC/subnets/firewalls, Cloud NAT, GKE, Cloud SQL, Cloud Storage, Pub/Sub, KMS, and Secret Manager.

## How to run
Run in numeric order (01-, 02-, 03-, …). Each creation script is followed by a validation script.

Example:
- `.\01-Context.ps1 -Prefix gc-tkt-prod -ProjectId my-project -Region us-central1`
- `.\03-Create-Network.ps1 -Prefix gc-tkt-prod -ProjectId my-project -Region us-central1`

## Notes
- GKE and Cloud SQL can take significant time to provision.
- These scripts provision infrastructure only; application deployment to GKE is a later step.

