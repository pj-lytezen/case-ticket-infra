# Metrics, Thresholds, and Operations

## Metrics (minimum set)

### Resolution & experience
- **Time to resolution** (session start → resolved).
- **First-contact resolution rate** (resolved without escalation).
- **Escalation rate** (percentage of sessions escalated to humans).
- **Re-contact rate** (same customer issue re-opened within N days).
- **CSAT / user rating** (if your channel supports it).

### Retrieval quality (Hybrid RAG)
- **Retrieval hit rate**: % of questions where relevant evidence exists and is retrieved.
- **Top-k coverage**: % of questions where the needed answer is contained in top-k retrieved chunks.
- **MRR / nDCG (offline)**: ranking quality on a labeled evaluation set.

### Model quality & safety
- **Grounding pass rate**: % of generated responses that include valid citations for all key claims.
- **Refusal correctness**: % of refusals that were appropriate (measured on labeled set).
- **Hallucination incidence**: detected unsupported claims per 1k conversations (manual audits + automated checks).

### Efficiency & cost
- **Latency**: p50/p95 end-to-end response time; break down by retrieval, rerank, generation.
- **Cost per resolved issue**: tokens + infrastructure + human minutes.
- **Agent handle time reduction**: for escalations, compare with baseline tickets.

## Thresholding strategy (how to choose the “LLM response threshold”)

### Recommended: multi-signal gating (instead of a single number)
Use a decision rule that combines:
- **Retrieval strength**: top score(s) exceed a minimum; at least N chunks meet a threshold.
- **Evidence coverage**: required question slots are supported (steps, eligibility, policy date, etc.).
- **Citation completeness**: answer includes valid references.
- **Evaluator outcome**: a post-generation checker confirms the answer is grounded and non-contradictory.

### Why multi-signal
Single-score thresholds are brittle across topics. Retrieval scores vary by content type; a combined gate is easier to calibrate and safer for “do not guess”.

### Calibration loop
1. Start conservative (more escalations).
2. Log evaluator reasons and retrieval artifacts.
3. Create a labeled set from real conversations (answerable vs not, correct vs incorrect).
4. Tune thresholds to minimize “incorrect answers” first, then improve deflection.

## Human escalation operations

### Ticket payload (what to include)
- Transcript + rolling context summary.
- Customer identifiers needed for the workflow (respecting privacy rules).
- Evidence pack (retrieved docs, scores, timestamps).
- Bot decision rationale (why it escalated).
- Suggested clarifying questions and likely intent classification.

### Continuing the conversation chain
- Treat agent messages as first-class `MESSAGE` records (`role=agent`).
- When the agent resolves the ticket, write a `resolution` event and generate a `CASE_SUMMARY`.

## Privacy, security, and compliance (minimum controls)
- **PII handling**: detect and redact or tokenize sensitive fields before indexing for retrieval; store raw separately with strict access.
- **Access control**: enforce document ACLs at retrieval time (never retrieve what the user isn’t entitled to see).
- **Retention**: configure retention for transcripts and embeddings based on policy; keep derived metrics longer if permitted.
- **Auditability**: store which sources were used to answer each response.

## Continuous improvement (closed loop)
- Use escalations to identify:
  - missing/dated documents,
  - ingestion errors (bad OCR, broken links),
  - and gaps in tagging/metadata.
- Promote high-quality case summaries into curated KB content over time.
- Add regression tests for top intents and known failure modes using real (sanitized) transcripts.

