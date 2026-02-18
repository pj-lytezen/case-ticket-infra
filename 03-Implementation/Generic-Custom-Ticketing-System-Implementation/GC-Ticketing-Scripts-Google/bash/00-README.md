# Google Cloud Bash Implementation Scripts (Generic Custom Ticketing System)

This folder contains **bash** equivalents of the PowerShell scripts in the parent directory.

## Prerequisites
- Bash 4+ (Linux/macOS; on Windows use WSL or Git Bash)
- `gcloud` (Google Cloud CLI)

## Authentication / Project selection
- `gcloud auth login`
- `gcloud config set project <PROJECT_ID>`

## How to run
Run scripts in numeric order. Each create script has a matching validation script.

Example:
- `./01-Context.sh --prefix gc-tkt-prod --project-id my-project --region us-central1 --zone us-central1-a`
- `./03-Create-Network.sh --prefix gc-tkt-prod --project-id my-project --region us-central1`
- `./11-Create-GKE.sh --prefix gc-tkt-prod --project-id my-project --region us-central1`

## Notes
- These scripts provision infrastructure only; application deployment to GKE is a later step.
- Many resources are named deterministically from `--prefix` to keep scripts idempotent.

