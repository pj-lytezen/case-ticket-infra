# Production Monthly Cost Estimate (AWS vs Azure vs GCP)

This estimate applies to the production design in `Design/Generic-Custom-Ticketing-System-Design/Generic-Custom-Ticketing-System-Design.md` and the integration strategy in `Strategy/Generic-Custom-Ticketing-System/`.

Numbers are **estimates** (region/pricing plan/discounts vary). Use this as a cost model you can refine with the provider calculators once you lock region, instance sizes, retention, and traffic.

## 1) Assumptions (baseline production)

### 1.1 Environment assumptions
- Region: a typical US region (prices differ by region)
- Availability: **multi-zone / multi-AZ** where supported
- Month length: **730 hours**
- Deployment: managed Kubernetes + managed PostgreSQL (lowest ops cost while keeping the app portable)

### 1.2 Workload assumptions (used for variable-cost items)
- Customer messages: ~**100k/month**
- Orchestrator turns (LLM calls): ~**10k/month**
- Retrieval queries: ~**30k/month**
- Documents indexed: ~**20k** chunks (grows over time)
- Queue traffic: ~**10M** messages/month (ingestion, outbox, sync)
- Logs ingested: ~**100 GB/month**, retained 30 days hot
- NAT processed egress: ~**500 GB/month** (this is the “danger” cost driver if private endpoints aren’t used)
- Internet egress to users: ~**200 GB/month**

### 1.3 Sizing assumptions (steady-state)

**Compute (`aws-eks_az-aks_gc-gke`)**
- Core node pool (always-on): **3 nodes**, ~2 vCPU / 8 GB each
- Worker node pool (spot/preemptible average): **1 node average** (scales with queue depth)

**Database (`aws-rds-postgresql_az-postgresql-flexible-server_gc-cloudsql-postgresql`)**
- HA / multi-zone enabled
- Storage: **200 GB** (gp3 / premium / pd-ssd equivalent)

**Object storage (`aws-s3_az-blob-storage_gc-cloud-storage`)**
- Storage: **500 GB** (docs + artifacts + attachments)

> LLM costs are separated because they vary dramatically by model and prompt size.

## 2) Summary totals (baseline, excluding LLM token charges)

These totals are designed to be “order-of-magnitude correct” for the baseline assumptions.

| Provider | Estimated monthly total (infra only) | Primary drivers |
|---|---:|---|
| AWS | **~$1.0k–$1.4k** | HA Postgres, NAT+endpoints, logs, K8s nodes |
| Azure | **~$1.1k–$1.6k** | HA Postgres, WAF/edge, logs, K8s nodes |
| GCP | **~$0.9k–$1.4k** | HA Postgres, NAT/egress, logs, GKE fee |

## 3) Detailed monthly estimate — AWS

Component equivalents referenced: `aws-vpc_az-vnet_gc-vpc`, `aws-eks_az-aks_gc-gke`, `aws-rds-postgresql_az-postgresql-flexible-server_gc-cloudsql-postgresql`, `aws-s3_az-blob-storage_gc-cloud-storage`, `aws-sqs_az-service-bus_gc-pubsub`.

### 3.1 Network + edge
- `aws-waf`: ~$20–$60
- `aws-api-gateway` (or `aws-alb`): ~$20–$80 (depends on request volume, payload sizes)
- `aws-nat-gateway` (2x AZ): ~$65–$90 (hourly) + **data processing** (often $10–$200+, depends on GB)
- `aws-privatelink` interface endpoints: ~$40–$120 (depends on how many endpoints * AZs)
- Data egress to internet (non-CDN): ~$10–$50+

### 3.2 Compute (Kubernetes)
- `aws-eks` control plane: ~$73
- EC2 nodes (core pool): ~$180–$350 (instance type dependent)
- EC2 spot nodes (workers avg 1): ~$10–$60
- EBS node volumes: ~$10–$40

### 3.3 Data plane
- `aws-rds-postgresql` Multi-AZ compute: **~$350–$900** (size dependent; this is usually your biggest fixed cost)
- RDS storage + backups: ~$20–$80
- `aws-s3` storage: ~$10–$30 (plus requests and retrieval)

### 3.4 Messaging + jobs
- `aws-sqs`: ~$2–$20 (request-volume dependent)
- `aws-eventbridge` schedules: ~$0–$10

### 3.5 Security + ops
- `aws-secrets-manager`: ~$5–$20 (secret count + API calls)
- `aws-kms`: typically low ($1–$20) unless heavy crypto ops
- `aws-cloudwatch` logs/metrics: ~$30–$150 (log ingest is the main driver)

**AWS baseline total (infra only):** ~**$1.0k–$1.4k/month**

## 4) Detailed monthly estimate — Azure

Component equivalents referenced: `aws-eks_az-aks_gc-gke`, `aws-rds-postgresql_az-postgresql-flexible-server_gc-cloudsql-postgresql`, `aws-privatelink_az-private-link_gc-private-service-connect`.

### 4.1 Network + edge
- `az-api-management` (consumption) or `az-application-gateway`: ~$30–$120
- WAF (`az-front-door-waf` or App Gateway WAF): ~$30–$150 (policy + traffic dependent)
- NAT (`az-nat-gateway`): ~$40–$120 (hourly + data processed/egress)
- Private endpoints (`az-private-link`): ~$40–$120 (endpoint count * zones)
- Internet egress: ~$10–$60+

### 4.2 Compute (Kubernetes)
- `az-aks` control plane: ~$0–$75 (depends on tier/pricing model)
- VM nodes (core pool): ~$180–$380
- Spot VM nodes (workers avg 1): ~$10–$70
- Managed disks for nodes: ~$10–$40

### 4.3 Data plane
- `az-postgresql-flexible-server` HA: **~$400–$1,000** (size + HA mode)
- Storage + backups: ~$20–$100
- `az-blob-storage`: ~$10–$30

### 4.4 Messaging + jobs
- `az-service-bus`: ~$5–$30
- Schedules/workflows (`az-logic-apps`): ~$0–$20 (depends on runs/connectors)

### 4.5 Security + ops
- `az-key-vault`: ~$5–$25 (ops + secret count)
- `az-monitor` logs/metrics: ~$30–$200 (ingest + retention)

**Azure baseline total (infra only):** ~**$1.1k–$1.6k/month**

## 5) Detailed monthly estimate — GCP

Component equivalents referenced: `aws-eks_az-aks_gc-gke`, `aws-rds-postgresql_az-postgresql-flexible-server_gc-cloudsql-postgresql`, `aws-nat-gateway_az-nat-gateway_gc-cloud-nat`.

### 5.1 Network + edge
- `gc-api-gateway` + `gc-https-load-balancer`: ~$20–$100 (requests + data)
- WAF (`gc-cloud-armor`): ~$20–$120
- NAT (`gc-cloud-nat`): ~$30–$150 (NAT gateway hourly + per-GB processing/egress can dominate)
- Private connectivity (`gc-private-service-connect`): ~$20–$120
- Internet egress: ~$10–$60+

### 5.2 Compute (Kubernetes)
- `gc-gke` cluster management fee (standard): ~$73 (varies by mode)
- GCE nodes (core pool): ~$130–$320
- Preemptible/spot node (workers avg 1): ~$10–$60
- Persistent disks for nodes: ~$10–$40

### 5.3 Data plane
- `gc-cloudsql-postgresql` HA: **~$350–$900**
- Storage + backups: ~$20–$100
- `gc-cloud-storage`: ~$10–$30

### 5.4 Messaging + jobs
- `gc-pubsub`: ~$2–$20
- `gc-cloud-scheduler`: ~$0–$5

### 5.5 Security + ops
- `gc-secret-manager`: ~$2–$15
- `gc-cloud-operations` logs/metrics: ~$30–$200

**GCP baseline total (infra only):** ~**$0.9k–$1.4k/month**

## 6) LLM and embeddings (separate line item)

Equivalent managed services: `aws-bedrock_az-openai_gc-vertex-ai`.

LLM cost depends on:
- model choice
- prompt length (rolling summaries reduce this)
- output length
- retry rate

For the baseline assumption (~10k turns/month), typical monthly LLM spend is often **$100–$2,000+**. Treat it as a configurable budget and instrument token usage by route/intent.

Cost control suggestions:
- Use smaller models for tagging/routing/summarization; reserve larger models for complex answers.
- Cache evidence packs and summaries per session.
- Fail closed (escalate) when retrieval is weak instead of attempting multiple expensive generations.

## 7) Cost saving suggestions (high impact)

### 7.1 Reduce NAT Gateway spend with private connectivity (where feasible)
NAT charges are often driven by **per-GB processing**, not just hourly cost.

Suggestions:
- Prefer private service connectivity:
  - `aws-privatelink_az-private-link_gc-private-service-connect`
- For AWS specifically, use **gateway endpoints** where possible (e.g., S3) to avoid NAT for that traffic.
- Route traffic to managed services over private endpoints so large log/doc transfers don’t traverse NAT.

Tradeoff:
- Private endpoints have per-hour charges; they usually win when you have meaningful data volume, strict security needs, or both.

### 7.2 Use spot/preemptible for workers (safe workloads)
- Put ingestion/embedding/outbox drainers on `aws-ec2-spot_az-spot-vm_gc-spot-vm`.
- Ensure workers are idempotent and checkpoint progress (queue + DB cursor).

### 7.3 Right-size and optimize PostgreSQL (largest fixed cost)
- Start with the smallest HA tier that meets p95 latency and CPU.
- Optimize indexes (FTS + vector) and keep embeddings in the same DB until scale forces separation.
- Use read replicas only when proven necessary (they add cost quickly).

### 7.4 Control observability spend
- Reduce log volume: structured logs, sampling, and shorter retention for verbose debug logs.
- Keep high-cardinality metrics under control (tag cardinality explodes costs).

### 7.5 Reduce egress
- Serve the agent UI via CDN (`aws-cloudfront_az-front-door_gc-cloud-cdn`).
- Keep large documents and attachments in object storage and avoid repeated downloads in services.

### 7.6 Commit discounts for steady-state
- AWS Savings Plans / Reserved Instances
- Azure Reserved VM Instances / Savings Plan
- GCP Committed Use Discounts

## 8) Next refinement steps (to turn this into a precise bill)

To produce a precise estimate per provider, fix:
1. Region
2. Instance types and counts (core vs worker pools)
3. DB tier (vCPU/RAM) + storage + IOPS
4. Log ingestion GB/month and retention
5. NAT processed GB/month (or endpoint counts if going private)
6. LLM model(s), average prompt/output tokens, and retry rates

If you provide target region and expected monthly message volume, I can regenerate this document with tighter numbers and a “small/medium/large” tier table.

