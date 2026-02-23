# case-ticket-infra
Infrastructure, strategy, and implementation artifacts for an AI-assisted customer support and case ticketing system.

## Project intent
This project defines a Generative AI workflow that automates customer support inquiries through a chatbot, with reliable escalation to a live representative when confidence or data availability falls below a defined threshold.

## Core requirements (from initial instructions)
- Conversation session management with unique identifiers and stored full questions optimized for RAG retrieval.
- Human escalation when answers are uncertain or data is missing, including full conversation history and a context summary.
- Post-resolution summaries with linked references (documents, URLs, paths), tagged questions, and traceable Q/A records for RAG and metrics.
- Metrics such as time-to-resolution, number of similar questions, and additional relevant operational KPIs.
- Hybrid RAG: combine document store search with vector search.

## Repository structure
- `01-Strategy/` Strategy definitions and workflow outlines.
- `02-Design/` System design and architecture materials.
- `03-Implementation/` Implementation details, scripts, and infrastructure artifacts.

## How to use this repo
1. Start with `01-Strategy/README.md` and the core docs (`Architecture.md`, `Data-and-RAG.md`, `Metrics-and-Ops.md`) to align on goals, workflows, and guardrails.
2. Review `02-Design/Generic-Custom-Ticketing-System-Design/Generic-Custom-Ticketing-System-Design.md` to map strategy into a deployable cloud architecture.
3. Use the provisioning scripts under `03-Implementation/Generic-Custom-Ticketing-System-Implementation/` to create infrastructure on your chosen cloud, then deploy application services separately.

## Strategy and architecture highlights
- `01-Strategy/Architecture.md` defines the reference workflow: channel adapter and gateway, conversation orchestrator, hybrid retrieval (document store + vector + full-text), evaluator, and escalation service wired into the ticketing system.
- `01-Strategy/Data-and-RAG.md` specifies the session/message/event/ticket data model, hybrid RAG pipeline, grounding rules, and post-resolution case summaries that feed future retrieval.
- `01-Strategy/Metrics-and-Ops.md` details operational metrics, multi-signal thresholds for escalation, privacy controls, and the continuous improvement loop.

## Integration variants
- Generic custom ticketing system guidance in `01-Strategy/Generic-Custom-Ticketing-System/` with webhook or polling integration patterns and a recommended data contract.
- Platform-specific strategies for Zendesk in `01-Strategy/Zendesk/` and ServiceNow in `01-Strategy/ServiceNow/` with field mappings and integration notes.

## Design and cost model
- `02-Design/Generic-Custom-Ticketing-System-Design/Generic-Custom-Ticketing-System-Design.md` maps the strategy into a cloud-agnostic component design with outbox/idempotency, network topology, and deployment sequencing.
- `02-Design/Generic-Custom-Ticketing-System-Design/Monthly-Cost-Estimate.md` provides baseline monthly cost estimates and tuning levers across AWS, Azure, and GCP.

## Implementation scripts
- `03-Implementation/Generic-Custom-Ticketing-System-Implementation/` contains PowerShell scripts for AWS, Azure, and GCP that provision infrastructure in ordered, idempotent steps.
- These scripts create cloud resources only; application deployment and Kubernetes manifests are intentionally out of scope.
